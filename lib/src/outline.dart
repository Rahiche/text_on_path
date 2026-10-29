import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'shaped_text.dart';

/// Each cluster's outline as vectors, for drawing sharp at any zoom and for SVG or PDF.
///
/// Flutter's paragraph engine doesn't hand back glyph outlines, so they're traced: each cluster is drawn alone at
/// [density] texels per logical pixel and the edge of its ink (where coverage crosses one half) is followed with
/// marching squares, then simplified to within [tolerance] logical pixels. At the default density the outline sits
/// within a few hundredths of a pixel of the glyph's edge at the text's own size.
class TextOutlines {
  TextOutlines._(this.contours, this.density, this.tolerance);

  /// Traces every cluster of [text].
  static Future<TextOutlines> trace(ShapedText text, {double density = 8, double tolerance = 0.02}) async {
    final contours = <List<Float64List>>[];
    for (final unit in text.units) {
      if (unit.ink.isEmpty) {
        contours.add(const []);
        continue;
      }
      // The cluster alone, a texel of clear round it so every edge closes.
      final rect = text.drawnRect(unit);
      final w = (rect.width * density).ceil() + 2, h = (rect.height * density).ceil() + 2;
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..translate(1, 1)
        ..scale(density)
        ..translate(-rect.left, -rect.top)
        ..drawParagraph(isolatedParagraph(text, unit.range), Offset.zero);
      final image = await recorder.endRecording().toImage(w, h);
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
      image.dispose();
      final alpha = Uint8List(w * h);
      for (var i = 0; i < alpha.length; i++) {
        alpha[i] = rgba[4 * i + 3];
      }
      contours.add([
        for (final loop in _trace(alpha, w, h))
          _toFlat(_simplify(loop, tolerance * density), rect.left, rect.top, density),
      ]);
    }
    return TextOutlines._(contours, density, tolerance);
  }

  /// For each cluster of the [ShapedText] (in the order of its units), its closed contours: x, y pairs in the flat
  /// run's coordinates. A cluster's contours fill by the even-odd rule: holes are contours inside contours.
  final List<List<Float64List>> contours;

  /// The density each cluster was traced at, in texels per logical pixel.
  final double density;

  /// How far, in logical pixels, a simplified contour may stray from the traced one.
  final double tolerance;

  /// How many points the outlines hold.
  int get points => contours.fold(0, (n, c) => n + c.fold(0, (m, loop) => m + loop.length ~/ 2));

  /// Texel-grid points to the flat run's coordinates: grid point (x, y) is the centre of texel (x, y), which sat a
  /// texel in from the image's corner.
  static Float64List _toFlat(Float64List loop, double left, double top, double density) {
    final out = Float64List(loop.length);
    for (var i = 0; i < loop.length; i += 2) {
      out[i] = left + (loop[i] + 0.5 - 1) / density;
      out[i + 1] = top + (loop[i + 1] + 0.5 - 1) / density;
    }
    return out;
  }

  /// Marching squares: the closed loops where [alpha] crosses one half, in texel-grid coordinates.
  static List<Float64List> _trace(Uint8List alpha, int w, int h) {
    const level = 127.5;
    double at(int x, int y) => (x < 0 || y < 0 || x >= w || y >= h) ? 0 : alpha[y * w + x].toDouble();
    // Each grid edge gets an id; a crossing on it is shared by the two cells either side.
    final stride = w + 2;
    int across(int x, int y) => ((y + 1) * stride + (x + 1)) * 2; // From (x, y) to (x + 1, y).
    int down(int x, int y) => ((y + 1) * stride + (x + 1)) * 2 + 1; // From (x, y) to (x, y + 1).
    final points = <int, (double, double)>{};
    final ends = <int>[]; // Two edge ids a segment.

    (double, double) crossing(int id) {
      final cached = points[id];
      if (cached != null) return cached;
      final cell = id >> 1, x = cell % stride - 1, y = cell ~/ stride - 1;
      final (double, double) p;
      if (id.isEven) {
        final a = at(x, y), b = at(x + 1, y);
        p = (x + (level - a) / (b - a), y.toDouble());
      } else {
        final a = at(x, y), b = at(x, y + 1);
        p = (x.toDouble(), y + (level - a) / (b - a));
      }
      return points[id] = p;
    }

    for (var y = -1; y < h; y++) {
      for (var x = -1; x < w; x++) {
        final tl = at(x, y), tr = at(x + 1, y), br = at(x + 1, y + 1), bl = at(x, y + 1);
        final index = (tl > level ? 8 : 0) | (tr > level ? 4 : 0) | (br > level ? 2 : 0) | (bl > level ? 1 : 0);
        if (index == 0 || index == 15) continue;
        final top = across(x, y), bottom = across(x, y + 1), left = down(x, y), right = down(x + 1, y);
        void segment(int a, int b) => ends
          ..add(a)
          ..add(b);
        final centre = (tl + tr + br + bl) / 4 > level;
        switch (index) {
          case 1 || 14:
            segment(left, bottom);
          case 2 || 13:
            segment(bottom, right);
          case 3 || 12:
            segment(left, right);
          case 4 || 11:
            segment(top, right);
          case 6 || 9:
            segment(top, bottom);
          case 7 || 8:
            segment(left, top);
          case 5:
            // Top-right and bottom-left inside: joined through the middle, or two separate corners.
            if (centre) {
              segment(left, top);
              segment(bottom, right);
            } else {
              segment(top, right);
              segment(left, bottom);
            }
          case 10:
            if (centre) {
              segment(top, right);
              segment(left, bottom);
            } else {
              segment(left, top);
              segment(bottom, right);
            }
        }
      }
    }

    // Link the segments into loops: every crossing is shared by exactly two of them.
    final byEdge = <int, List<int>>{};
    for (var s = 0; s < ends.length ~/ 2; s++) {
      (byEdge[ends[2 * s]] ??= []).add(s);
      (byEdge[ends[2 * s + 1]] ??= []).add(s);
    }
    final used = List<bool>.filled(ends.length ~/ 2, false);
    final loops = <Float64List>[];
    for (var start = 0; start < used.length; start++) {
      if (used[start]) continue;
      final loop = <double>[];
      var s = start, edge = ends[2 * start];
      while (!used[s]) {
        used[s] = true;
        final (px, py) = crossing(edge);
        loop
          ..add(px)
          ..add(py);
        edge = ends[2 * s] == edge ? ends[2 * s + 1] : ends[2 * s];
        final next = byEdge[edge]!;
        s = next[0] == s ? (next.length > 1 ? next[1] : s) : next[0];
      }
      if (loop.length >= 6) loops.add(Float64List.fromList(loop));
    }
    return loops;
  }

  /// Ramer–Douglas–Peucker on a closed loop: the fewest of its points that stay within [epsilon] of it.
  static Float64List _simplify(Float64List loop, double epsilon) {
    final n = loop.length ~/ 2;
    if (n < 4) return loop;
    // Split the loop at its first point and the point furthest from it, and simplify both halves.
    var far = 0;
    var farthest = -1.0;
    for (var i = 1; i < n; i++) {
      final d = math.pow(loop[2 * i] - loop[0], 2) + math.pow(loop[2 * i + 1] - loop[1], 2);
      if (d > farthest) {
        farthest = d.toDouble();
        far = i;
      }
    }
    final keep = List<bool>.filled(n + 1, false)
      ..[0] = true
      ..[far] = true
      ..[n] = true;
    double px(int i) => loop[2 * (i % n)];
    double py(int i) => loop[2 * (i % n) + 1];
    final stack = <(int, int)>[(0, far), (far, n)];
    while (stack.isNotEmpty) {
      final (a, b) = stack.removeLast();
      if (b - a < 2) continue;
      final ax = px(a), ay = py(a), bx = px(b), by = py(b);
      final dx = bx - ax, dy = by - ay;
      final length = math.sqrt(dx * dx + dy * dy);
      var worst = a, worstDistance = -1.0;
      for (var i = a + 1; i < b; i++) {
        final d = length > 1e-9
            ? ((px(i) - ax) * dy - (py(i) - ay) * dx).abs() / length
            : math.sqrt(math.pow(px(i) - ax, 2) + math.pow(py(i) - ay, 2));
        if (d > worstDistance) {
          worstDistance = d;
          worst = i;
        }
      }
      if (worstDistance > epsilon) {
        keep[worst] = true;
        stack
          ..add((a, worst))
          ..add((worst, b));
      }
    }
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      if (keep[i]) {
        out
          ..add(loop[2 * i])
          ..add(loop[2 * i + 1]);
      }
    }
    return Float64List.fromList(out);
  }
}
