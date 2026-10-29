import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'curve.dart';
import 'outline.dart';
import 'shaped_text.dart';

/// How each cluster is put on the curve.
enum TextOnPathMode {
  /// Each cluster stands rigid on the curve at the middle of its box, turned to the tangent there: what text-on-path
  /// packages do. Letters keep their shape, but joins open on the outside of a bend and overlap on the inside.
  rigid,

  /// The whole run bent along the curve, each point carried out along the curve's normal, as SVG's
  /// `textPath method="stretch"` would. Joins stay closed, but letters stretch on the outside of a bend and squash on
  /// the inside.
  warp,

  /// Letters stand rigid, as in [rigid], but the rows they join on follow the curve, so joins stay closed and letters
  /// keep their shape.
  joined,
}

/// How text is made to fill a length.
enum TextOnPathFit {
  /// Its natural length.
  none,

  /// Wider gaps between words.
  spacing,

  /// Every gap between clusters a little wider. In [TextOnPathMode.joined], a joined pair isn't pulled apart: the
  /// stroke joining them grows.
  tracking,

  /// Arabic's own way: in each word, the join a calligrapher would stretch is drawn out. Other scripts fall back to
  /// [tracking].
  kashida,
}

/// Where each point of a [ShapedText] goes on a [PathCurve].
///
/// The text's baseline runs along the curve, centred at [position] (a fraction of the curve's length). Build one each
/// time the curve or the mode changes; it's cheap next to shaping. [vertices] gives the mesh that draws it.
class TextOnPathPlacement {
  TextOnPathPlacement(
    this.text,
    this.curve, {
    this.mode = TextOnPathMode.joined,
    this.position = 0.5,
    this.fit = TextOnPathFit.none,
    double? fitLength,
    this.transition = 0.18,
  }) {
    _place(fitLength);
  }

  /// The shaped text.
  final ShapedText text;

  /// The curve its baseline runs along.
  final PathCurve curve;

  /// How the clusters are placed.
  final TextOnPathMode mode;

  /// Where along the curve the middle of the text goes, as a fraction of its length.
  final double position;

  /// How the text fills [fitLength].
  final TextOnPathFit fit;

  /// How far, in em, the joining rows fade into rigid letters, in [TextOnPathMode.joined].
  final double transition;

  /// The length the text takes on the curve.
  double get length => _end - _start;

  /// The length it would take unfitted, and whether it's longer than the length it was to fit.
  double get naturalLength => _natural;
  bool get overflows => _overflow;

  late final CurveTrack _base = trackOf(curve);
  late final CurveTrack _join; // The curve the joining rows run along: the baseline track offset up to the band.
  late double _hc; // How far the joining rows are above the baseline.
  late Float64List _s; // Where each cluster's anchor lands on the curve.
  late Float64List _lambda; // The same, measured along the joining rows' curve.
  late Float64List _frames; // The curve at each anchor: x, y, tx, ty.
  late Float64List _extra; // Extra length at each pair's boundary, from fitting.
  late double _start, _end, _natural;
  bool _overflow = false;
  late List<_Ramp?> _leftRamp, _rightRamp; // Each cluster's joining rows stretched at its joins.
  List<List<(_Seam, bool)>> _seams = const []; // Each cluster's mismatched joins, and whether it's their left side.
  final _bridges = <int, _Bridge>{}; // Joins whose sides land apart, by the left cluster's index.
  final _frame = Float64List(5);

  void _place(double? fitLength) {
    final band = text.band;
    _hc = band == null ? 0 : text.baseline - band.center;
    _join = _hc == 0 ? _base : _base.offset(_hc);
    final n = text.units.length;
    _extra = Float64List(math.max(0, n - 1));
    _s = Float64List(n);

    _layOut();
    _natural = length;
    if (fit != TextOnPathFit.none) {
      final target = fitLength ?? (curve.closed ? curve.length - text.fontSize : curve.length);
      final more = target - _natural;
      _overflow = more < 0;
      if (more > 0) {
        final weights = _fitWeights();
        final total = weights.fold(0.0, (a, b) => a + b);
        if (total > 0) {
          for (var i = 0; i < _extra.length; i++) {
            _extra[i] = more * weights[i] / total;
          }
          _layOut();
        }
      }
    }

    _frames = Float64List(4 * n);
    _lambda = Float64List(n);
    for (var i = 0; i < n; i++) {
      _base.eval(_s[i], _frame);
      _frames.setRange(4 * i, 4 * i + 4, _frame);
      _lambda[i] = _base.mapTo(_join, _s[i]);
    }

    // In joined mode letters stand rigid, so a join's two sides can land apart along the joining rows' curve: on the
    // outside of a bend, or where fitting added length. Where the joining stroke runs flat, the gap is bridged with
    // the stroke's own cross-section at the join, drawn along the curve, as a tatweel would be. Where they'd overlap
    // instead, the joining rows are squeezed across the join's bare stroke.
    _leftRamp = List.filled(n, null);
    _rightRamp = List.filled(n, null);
    _bridges.clear();
    if (mode == TextOnPathMode.joined && band != null) {
      final minZone = 0.08 * text.fontSize;
      for (final p in text.neighbours) {
        if (!p.joins || !p.inBand) continue;
        final a = text.units[p.left], b = text.units[p.right];
        final delta = _lambda[p.right] - _lambda[p.left] - (b.anchor - a.anchor);
        // A flat stroke is drawn out along the curve; a sloping one would kink, so it's pulled shut instead (below).
        if (delta > 0.01 && p.canDrawOut) {
          // It spans every row the stroke crosses in, and at least the rows that follow the curve exactly.
          var top = band.top - _bandMargin, bottom = band.bottom + _bandMargin;
          for (final (y0, y1) in p.crossing) {
            top = math.min(top, y0);
            bottom = math.max(bottom, y1);
          }
          _bridges[p.left] = _Bridge(p, _lambda[p.left] + (p.x - a.anchor), delta, top, bottom);
        } else if (delta < -0.01) {
          var zl = p.leftBare, zr = p.rightBare;
          if (zl + zr < minZone) {
            final more = (minZone - zl - zr) / 2;
            zl += more;
            zr += more;
          }
          final ramp = _Ramp(p.x - zl, p.x + zr, delta);
          _rightRamp[p.left] = ramp;
          _leftRamp[p.right] = ramp;
        }
      }
    }

    // Where a join's sides still don't meet (rows outside the joining rows, like Nastaliq's sloping joins or a script
    // hand's high ones), each side's copy of the boundary is pulled to where it should be, the pull fading out over a
    // short distance: to the bridge's end, for a bridged join, or else halfway to the other side's copy.
    _seams = List.filled(n, const []);
    if (mode == TextOnPathMode.joined) {
      final seams = List.generate(n, (_) => <(_Seam, bool)>[]);
      final all = <(_Seam, UnitPair, _Bridge?)>[];
      final a = Float64List(2), b = Float64List(2);
      final step = math.max(0.5, 1 / text.scale);
      for (final p in text.neighbours) {
        if (!p.joins) continue;
        final bridge = _bridges[p.left];
        for (final (y0, y1) in p.crossing) {
          final rows = math.max(2, ((y1 - y0) / step).ceil() + 1);
          final left = Float64List(2 * rows), right = Float64List(2 * rows);
          for (var r = 0; r < rows; r++) {
            final y = y0 + (y1 - y0) * r / (rows - 1);
            _map(p.left, p.x, y, a);
            _map(p.right, p.x, y, b);
            if (bridge != null) {
              final start = _onJoin(bridge.from, y), end = _onJoin(bridge.from + bridge.delta, y);
              left[2 * r] = start.dx - a[0];
              left[2 * r + 1] = start.dy - a[1];
              right[2 * r] = end.dx - b[0];
              right[2 * r + 1] = end.dy - b[1];
            } else {
              left[2 * r] = (b[0] - a[0]) / 2;
              left[2 * r + 1] = (b[1] - a[1]) / 2;
              right[2 * r] = -left[2 * r];
              right[2 * r + 1] = -left[2 * r + 1];
            }
          }
          // Even a join that already meets gets a seam: a neighbouring join's pull may reach it.
          final seam = _Seam(p.x, y0, y1, left, right, 0.3 * text.fontSize);
          seams[p.left].add((seam, true));
          seams[p.right].add((seam, false));
          all.add((seam, p, bridge));
        }
      }
      _seams = seams;
      // A cluster's joins can lie close enough for one's pull to move another's boundary too. Correct each by what's
      // left once every pull is applied, a few times over.
      for (var pass = 0; pass < 3; pass++) {
        for (final (seam, p, bridge) in all) {
          final rows = seam.left.length ~/ 2;
          for (var r = 0; r < rows; r++) {
            final y = seam.top + (seam.bottom - seam.top) * r / (rows - 1);
            _map(p.left, p.x, y, a);
            _map(p.right, p.x, y, b);
            final (tx0, ty0, tx1, ty1) = bridge != null
                ? (() {
                    final start = _onJoin(bridge.from, y), end = _onJoin(bridge.from + bridge.delta, y);
                    return (start.dx, start.dy, end.dx, end.dy);
                  })()
                : ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
            seam.left[2 * r] += tx0 - a[0];
            seam.left[2 * r + 1] += ty0 - a[1];
            seam.right[2 * r] += tx1 - b[0];
            seam.right[2 * r + 1] += ty1 - b[1];
          }
        }
      }
      // Seams that move nothing cost every point a distance check: drop them.
      bool idle(_Seam seam) => seam.left.every((v) => v.abs() < 0.005) && seam.right.every((v) => v.abs() < 0.005);
      for (final list in seams) {
        list.removeWhere((entry) => idle(entry.$1));
      }
    }
  }

  /// Places every anchor, with the extra lengths from fitting, and centres the text.
  void _layOut() {
    final units = text.units;
    if (units.isEmpty) {
      _start = _end = 0;
      return;
    }
    // Curvature depends on where the text sits, so lay it out from a start, centre it, and repeat until it settles.
    var start = position * curve.length - text.width / 2;
    for (var pass = 0; pass < 4; pass++) {
      final centred = position * curve.length - _anchorsFrom(start) / 2;
      if ((centred - start).abs() < 0.01) break;
      start = centred;
    }
    _anchorsFrom(start);
  }

  /// Places the anchors from [start] and returns the text's length.
  double _anchorsFrom(double start) {
    final units = text.units;
    var s = start + units.first.anchor * _spacing(start);
    _s[0] = s;
    for (var i = 0; i + 1 < units.length; i++) {
      final dx = units[i + 1].anchor - units[i].anchor;
      s += dx * _spacing(s + dx / 2) + _extra[i];
      _s[i + 1] = s;
    }
    _start = start;
    _end = s + (text.width - units.last.anchor) * _spacing(s);
    return _end - _start;
  }

  /// How much curve a pixel of the flat run takes. In joined mode, on the inside of a bend, letters are spaced along
  /// the joining rows rather than the baseline, so a join is only ever stretched, never squeezed.
  double _spacing(double s) {
    if (mode != TextOnPathMode.joined || _hc == 0) return 1;
    final stretch = 1 + _curvature(s) * _hc;
    return stretch >= 1 ? 1 : 1 / math.max(stretch, 0.2);
  }

  double _curvature(double s) {
    _base.eval(s, _frame);
    return _frame[4];
  }

  List<double> _fitWeights() {
    final pairs = text.neighbours;
    final weights = List<double>.filled(pairs.length, 0);
    var how = fit;
    if (how == TextOnPathFit.kashida && !_isArabic(text.text)) how = TextOnPathFit.tracking;
    switch (how) {
      case TextOnPathFit.none:
        break;
      case TextOnPathFit.spacing:
        for (var i = 0; i < pairs.length; i++) {
          if (!pairs[i].touching) weights[i] = 1;
        }
      case TextOnPathFit.tracking:
        // Every gap, and every join that can be drawn out; a sloping join would have to bend to take it.
        for (var i = 0; i < pairs.length; i++) {
          if (!pairs[i].joins || pairs[i].canDrawOut) weights[i] = 1;
        }
      case TextOnPathFit.kashida:
        for (final i in _kashidas()) {
          weights[i] = 1;
        }
    }
    if (weights.every((w) => w == 0)) {
      // Nothing to stretch: open the gaps between words, or else every gap.
      for (var i = 0; i < pairs.length; i++) {
        if (!pairs[i].touching) weights[i] = 1;
      }
      if (weights.every((w) => w == 0)) weights.fillRange(0, weights.length, 1);
    }
    return weights;
  }

  /// One join a word, the one a calligrapher would draw out: after seen, sheen, sad or dad; else before the word's
  /// last letter; else any join.
  List<int> _kashidas() {
    final t = text.text;
    final word = List<int>.filled(t.length + 1, 0);
    for (var i = 0, w = 0; i < t.length; i++) {
      if (t[i].trim().isEmpty) w++;
      word[i] = w;
    }
    bool lastOfWord(TextRange r) => r.end >= t.length || t[r.end].trim().isEmpty;

    final best = <int, (int, int, int)>{}; // word -> (priority, -position, pair)
    for (var i = 0; i < text.neighbours.length; i++) {
      final p = text.neighbours[i];
      if (!p.canDrawOut) continue;
      final a = text.units[p.left].range, b = text.units[p.right].range;
      final (first, second) = a.start < b.start ? (a, b) : (b, a);
      final f = t[first.start], s = t[second.start];
      if (f == 'ل' && 'اأإآ'.contains(s)) continue;
      final priority = 'سشصض'.contains(f) ? 0 : (lastOfWord(second) ? 1 : 2);
      final key = (priority, -second.start, i);
      final w = word[first.start];
      final current = best[w];
      if (current == null || key.$1 < current.$1 || (key.$1 == current.$1 && key.$2 < current.$2)) best[w] = key;
    }
    return [for (final v in best.values) v.$3];
  }

  static bool _isArabic(String s) => s.runes.any(
        (c) => (c >= 0x0600 && c <= 0x06FF) || (c >= 0x0750 && c <= 0x077F) || (c >= 0x08A0 && c <= 0x08FF),
      );

  /// Where the flat point ([x], [y]) of cluster [unit] lands.
  Offset map(int unit, double x, double y) {
    final out = Float64List(2);
    _map(unit, x, y, out);
    return Offset(out[0], out[1]);
  }

  void _map(int i, double x, double y, Float64List out) {
    final u = text.units[i];
    final b = text.baseline;
    switch (mode) {
      case TextOnPathMode.rigid:
        _rigid(i, u, x, y, out);
      case TextOnPathMode.warp:
        // The flat run's x is arc length along the baseline; the fitted extras open up at each pair's boundary.
        var s = _s[i] + (x - u.anchor);
        if (i > 0 && x < text.neighbours[i - 1].x) s -= _extra[i - 1];
        if (i + 1 < text.units.length && x > text.neighbours[i].x) s += _extra[i];
        _base.eval(s, _frame);
        out[0] = _frame[0] + (b - y) * _frame[3];
        out[1] = _frame[1] - (b - y) * _frame[2];
      case TextOnPathMode.joined:
        _joined(i, u, x, y, out);
        for (final (seam, isLeft) in _seams[i]) {
          seam.pull(x, y, isLeft, out);
        }
    }
  }

  /// The joining rows follow the curve; the rest of the letter stands rigid; between, one eases into the other.
  void _joined(int i, TextUnit u, double x, double y, Float64List out) {
    final w = _weight(y);
    if (w == 0) {
      _rigid(i, u, x, y, out);
      return;
    }
    var l = _lambda[i] + (x - u.anchor);
    final left = _leftRamp[i], right = _rightRamp[i];
    if (left != null) l -= left.delta * (1 - left.at(x));
    if (right != null) l += right.delta * right.at(x);
    _join.eval(l, _frame);
    final c = text.baseline - _hc;
    final bx = _frame[0] + (c - y) * _frame[3];
    final by = _frame[1] - (c - y) * _frame[2];
    if (w == 1) {
      out[0] = bx;
      out[1] = by;
      return;
    }
    _rigid(i, u, x, y, out);
    out[0] = w * bx + (1 - w) * out[0];
    out[1] = w * by + (1 - w) * out[1];
  }

  void _rigid(int i, TextUnit u, double x, double y, Float64List out) {
    final f = 4 * i;
    final dx = x - u.anchor, up = text.baseline - y;
    out[0] = _frames[f] + dx * _frames[f + 2] + up * _frames[f + 3];
    out[1] = _frames[f + 1] + dx * _frames[f + 3] - up * _frames[f + 2];
  }

  double get _bandMargin => 0.03 * text.fontSize + 0.5;

  /// How much the flat run's row [y] follows the curve in [TextOnPathMode.joined]: 1 in the joining rows, easing to
  /// 0 where letters stand rigid. (Joins outside those rows are pulled shut besides.)
  double rowWeight(double y) => mode == TextOnPathMode.joined ? _weight(y) : (mode == TextOnPathMode.warp ? 1 : 0);

  /// How much a row follows the curve rather than its letter: 1 in the joining rows, easing to 0 a [transition] away.
  double _weight(double y) {
    final band = text.band;
    if (band == null) return 0;
    final margin = _bandMargin;
    final d =
        y < band.top - margin ? band.top - margin - y : (y > band.bottom + margin ? y - band.bottom - margin : 0.0);
    if (d <= 0) return 1;
    final t = (d / (transition * text.fontSize)).clamp(0.0, 1.0);
    return 1 - t * t * (3 - 2 * t);
  }

  /// The mesh's spacing, in logical pixels of the flat run.
  double get meshSpacing => (text.fontSize / 24).clamp(1.0, 4.0);

  /// The grid over cluster [i]'s ink, [step] apart: its columns' and rows' places in the flat run. The columns take in
  /// the boundaries of the cluster's joins, so the mesh carries a join's two sides exactly where the mapping does.
  (Float64List, Float64List) _grid(int i, double step) {
    final ink = text.drawnRect(text.units[i]);
    final nx = math.max(2, (ink.width / step).ceil() + 1), ny = math.max(2, (ink.height / step).ceil() + 1);
    final xs = [for (var c = 0; c < nx; c++) ink.left + ink.width * c / (nx - 1)];
    for (final p in text.neighbours) {
      if (p.joins && (p.left == i || p.right == i) && p.x > ink.left && p.x < ink.right) xs.add(p.x);
    }
    xs.sort();
    final columns = <double>[xs.first];
    for (final x in xs.skip(1)) {
      if (x - columns.last > 0.05) {
        columns.add(x);
      } else if (text.neighbours.any((p) => p.x == x)) {
        columns.last = x;
      }
    }
    return (
      Float64List.fromList(columns),
      Float64List.fromList([for (var r = 0; r < ny; r++) ink.top + ink.height * r / (ny - 1)]),
    );
  }

  late final _grids = [for (var i = 0; i < text.units.length; i++) _grid(i, meshSpacing)];

  /// Where the drawn mesh puts the flat point ([x], [y]) of cluster [unit]: [map] at the corners of the mesh triangle
  /// it falls in, blended across the triangle as the GPU does.
  Offset rendered(int unit, double x, double y) {
    final (xs, ys) = _grids[unit];
    int cell(Float64List at, double v) {
      var lo = 0, hi = at.length - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) >> 1;
        if (at[mid] <= v) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    final c = cell(xs, x), r = cell(ys, y);
    final fx = ((x - xs[c]) / (xs[c + 1] - xs[c])).clamp(0.0, 1.0);
    final fy = ((y - ys[r]) / (ys[r + 1] - ys[r])).clamp(0.0, 1.0);
    Offset corner(int cc, int rr) => map(unit, xs[cc], ys[rr]);
    final a = corner(c, r), e = corner(c + 1, r + 1);
    // Each cell is two triangles, split along the diagonal from its top-left corner.
    if (fx >= fy) {
      final b = corner(c + 1, r);
      return a + (b - a) * (fx - fy) + (e - a) * fy;
    }
    final d = corner(c, r + 1);
    return a + (d - a) * (fy - fx) + (e - a) * fx;
  }

  /// Where the drawn text puts a join's boundary at the flat row [y], as pairs of copies that should meet: the left
  /// cluster's and the right one's or, where the join is bridged, the left cluster's and the bridge's start, then the
  /// bridge's end and the right cluster's.
  List<(Offset, Offset)> joinCopies(UnitPair pair, double y) {
    final left = rendered(pair.left, pair.x, y), right = rendered(pair.right, pair.x, y);
    final bridge = _bridges[pair.left];
    if (bridge == null || y < bridge.top || y > bridge.bottom) return [(left, right)];
    return [(left, _onJoin(bridge.from, y)), (_onJoin(bridge.from + bridge.delta, y), right)];
  }

  /// The point [y] rows into the joining rows' curve at [distance] along it.
  Offset _onJoin(double distance, double y) {
    _join.eval(distance, _frame);
    final c = text.baseline - _hc;
    return Offset(_frame[0] + (c - y) * _frame[3], _frame[1] - (c - y) * _frame[2]);
  }

  /// The mesh: a grid over each cluster's ink, mapped onto the curve, sampling [atlas] (by default
  /// [ShapedText.atlas]; an atlas drawn from some other text is passed over for it). Drawn with a paint whose shader is
  /// an [ImageShader] of the atlas's image (see [paint]).
  List<ui.Vertices> vertices({TextAtlas? atlas, double? spacing}) {
    final source = atlas != null && atlas.isFor(text) ? atlas : text.atlas;
    final step = spacing ?? meshSpacing;
    final out = <ui.Vertices>[];
    final pos = <double>[], tex = <double>[], idx = <int>[];
    final p = Float64List(2);
    void flush() {
      if (idx.isEmpty) return;
      out.add(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.fromList(pos),
          textureCoordinates: Float32List.fromList(tex),
          indices: Uint16List.fromList(idx),
        ),
      );
      pos.clear();
      tex.clear();
      idx.clear();
    }

    for (var i = 0; i < text.units.length; i++) {
      if (text.units[i].ink.isEmpty) continue;
      final (xs, ys) = spacing == null ? _grids[i] : _grid(i, step);
      final nx = xs.length, ny = ys.length;
      if (pos.length ~/ 2 + nx * ny > 65535) flush();
      final first = pos.length ~/ 2;
      for (final y in ys) {
        for (final x in xs) {
          _map(i, x, y, p);
          pos
            ..add(p[0])
            ..add(p[1]);
          final t = source.texel(i, x, y);
          tex
            ..add(t.dx)
            ..add(t.dy);
        }
      }
      for (var r = 0; r + 1 < ny; r++) {
        for (var c = 0; c + 1 < nx; c++) {
          final a = first + r * nx + c, b = a + 1, d = a + nx, e = d + 1;
          idx.addAll([a, b, e, a, e, d]);
        }
      }
    }
    // Each bridge: a strip along the curve, every column of it the stroke's cross-section at the join.
    for (final bridge in _bridges.values) {
      final x = bridge.pair.x - 0.75;
      final top = bridge.top, bottom = bridge.bottom;
      final nx = math.max(2, ((bridge.delta + 1) / step).ceil() + 1);
      if (pos.length ~/ 2 + 2 * nx > 65535) flush();
      final first = pos.length ~/ 2;
      for (final y in [top, bottom]) {
        final t = source.texel(bridge.pair.left, x, y);
        for (var c = 0; c < nx; c++) {
          final o = _onJoin(bridge.from - 0.5 + (bridge.delta + 1) * c / (nx - 1), y);
          pos
            ..add(o.dx)
            ..add(o.dy);
          tex
            ..add(t.dx)
            ..add(t.dy);
        }
      }
      for (var c = 0; c + 1 < nx; c++) {
        final a = first + c, b = a + 1, d = a + nx, e = d + 1;
        idx.addAll([a, b, e, a, e, d]);
      }
    }
    flush();
    return out;
  }

  /// Draws the text with [canvas], from [atlas] (by default [ShapedText.atlas]; an atlas drawn from some other text,
  /// say while a new one is drawn for it, is passed over for it).
  void paint(Canvas canvas, {TextAtlas? atlas, FilterQuality filterQuality = FilterQuality.medium}) {
    final source = atlas != null && atlas.isFor(text) ? atlas : text.atlas;
    final paint = Paint()..shader = source.shader(filterQuality);
    for (final v in vertices(atlas: source)) {
      canvas.drawVertices(v, BlendMode.srcOver, paint);
      v.dispose();
    }
  }

  /// The placed text as vector shapes, from [outlines] traced from [text]: for each cluster and each bridge, its
  /// closed polygons (x, y pairs) in this placement's coordinates, filled together by the even-odd rule.
  ///
  /// Every edge is cut into pieces at most [step] logical pixels long before it's mapped, so it bends with the curve.
  List<List<Float64List>> outlineShapes(TextOutlines outlines, {double step = 1}) {
    final shapes = <List<Float64List>>[];
    for (var i = 0; i < text.units.length; i++) {
      final loops = outlineOf(outlines, i, step: step);
      if (loops.isNotEmpty) shapes.add(loops);
    }
    // Each bridge: the stroke's cross-section at the join, read off the left cluster's outline, drawn along the
    // curve, half a pixel into either cluster so no seam shows.
    for (final bridge in _bridges.values) {
      final x = bridge.pair.x - 0.75;
      final ys = <double>[];
      for (final loop in outlines.contours[bridge.pair.left]) {
        final n = loop.length ~/ 2;
        for (var k = 0; k < n; k++) {
          final ax = loop[2 * k], ay = loop[2 * k + 1];
          final bx = loop[2 * ((k + 1) % n)], by = loop[2 * ((k + 1) % n) + 1];
          if ((ax <= x) != (bx <= x)) ys.add(ay + (x - ax) / (bx - ax) * (by - ay));
        }
      }
      ys.sort();
      final loops = <Float64List>[];
      final n = math.max(2, ((bridge.delta + 1) / step).ceil() + 1);
      for (var k = 0; k + 1 < ys.length; k += 2) {
        final y0 = math.max(ys[k], bridge.top), y1 = math.min(ys[k + 1], bridge.bottom);
        if (y1 <= y0) continue;
        final points = <double>[];
        for (var c = 0; c < 2 * n; c++) {
          final along = c < n ? c : 2 * n - 1 - c;
          final o = _onJoin(bridge.from - 0.5 + (bridge.delta + 1) * along / (n - 1), c < n ? y0 : y1);
          points
            ..add(o.dx)
            ..add(o.dy);
        }
        loops.add(Float64List.fromList(points));
      }
      if (loops.isNotEmpty) shapes.add(loops);
    }
    return shapes;
  }

  /// Cluster [unit]'s contours from [outlines], placed: closed polygons (x, y pairs) filled by the even-odd rule, every
  /// edge cut into pieces at most [step] logical pixels long before it's mapped.
  List<Float64List> outlineOf(TextOutlines outlines, int unit, {double step = 1}) {
    final out = Float64List(2);
    final loops = <Float64List>[];
    for (final loop in outlines.contours[unit]) {
      final mapped = <double>[];
      final n = loop.length ~/ 2;
      for (var k = 0; k < n; k++) {
        final ax = loop[2 * k], ay = loop[2 * k + 1];
        final bx = loop[2 * ((k + 1) % n)], by = loop[2 * ((k + 1) % n) + 1];
        final pieces = math.max(1, (math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) / step).ceil());
        for (var p = 0; p < pieces; p++) {
          final t = p / pieces;
          _map(unit, ax + t * (bx - ax), ay + t * (by - ay), out);
          mapped
            ..add(out[0])
            ..add(out[1]);
        }
      }
      loops.add(Float64List.fromList(mapped));
    }
    return loops;
  }

  /// [outlineShapes] as paths.
  List<Path> outlinePaths(TextOutlines outlines) => [
        for (final shape in outlineShapes(outlines))
          Path()
            ..fillType = PathFillType.evenOdd
            ..addPolygonLoops(shape),
      ];

  /// Draws the text with [canvas] from its outlines: sharp at any zoom.
  void paintOutlines(Canvas canvas, TextOutlines outlines, {Color? color}) {
    final paint = Paint()..color = color ?? text.style.color ?? const Color(0xff000000);
    for (final path in outlinePaths(outlines)) {
      canvas.drawPath(path, paint);
    }
  }

  /// The text as an SVG document, from its outlines: one even-odd path per cluster and per bridge, [margin] logical
  /// pixels clear round them.
  String toSvg(TextOutlines outlines, {Color? color, double margin = 4}) {
    final shapes = outlineShapes(outlines);
    final box = _bounds(shapes).inflate(margin);
    final c = color ?? text.style.color ?? const Color(0xff000000);
    String n(double v) => v.toStringAsFixed(2);
    String channel(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
    final fill = '#${channel(c.r)}${channel(c.g)}${channel(c.b)}';
    final out = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="${n(box.left)} ${n(box.top)} ${n(box.width)} '
          '${n(box.height)}" width="${n(box.width)}" height="${n(box.height)}">');
    for (final shape in shapes) {
      out.write('<path fill="$fill"${c.a < 1 ? ' fill-opacity="${n(c.a)}"' : ''} fill-rule="evenodd" d="');
      for (final loop in shape) {
        for (var k = 0; k < loop.length; k += 2) {
          out.write('${k == 0 ? 'M' : 'L'}${n(loop[k])} ${n(loop[k + 1])}');
        }
        out.write('Z');
      }
      out.writeln('"/>');
    }
    out.writeln('</svg>');
    return out.toString();
  }

  /// The text as a one-page PDF, from its outlines, the page fitted to them with [margin] points clear round them (a
  /// logical pixel to a point).
  Uint8List toPdf(TextOutlines outlines, {Color? color, double margin = 4}) {
    final shapes = outlineShapes(outlines);
    final box = _bounds(shapes).inflate(margin);
    final c = color ?? text.style.color ?? const Color(0xff000000);
    String n(double v) => v.toStringAsFixed(2);
    final content = StringBuffer('${n(c.r)} ${n(c.g)} ${n(c.b)} rg\n');
    for (final shape in shapes) {
      for (final loop in shape) {
        for (var k = 0; k < loop.length; k += 2) {
          // PDF's y runs up the page.
          content.write('${n(loop[k] - box.left)} ${n(box.bottom - loop[k + 1])} ${k == 0 ? 'm' : 'l'}\n');
        }
        content.write('h\n');
      }
      content.write('f*\n');
    }
    final stream = content.toString();
    final objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${n(box.width)} ${n(box.height)}] /Contents 4 0 R '
          '/Resources << >> >>',
      '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
    ];
    final pdf = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(pdf.length);
      pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = pdf.length;
    pdf.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      pdf.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    pdf.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    return Uint8List.fromList(pdf.toString().codeUnits);
  }

  static Rect _bounds(List<List<Float64List>> shapes) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final shape in shapes) {
      for (final loop in shape) {
        for (var k = 0; k < loop.length; k += 2) {
          l = math.min(l, loop[k]);
          r = math.max(r, loop[k]);
          t = math.min(t, loop[k + 1]);
          b = math.max(b, loop[k + 1]);
        }
      }
    }
    return l.isFinite ? Rect.fromLTRB(l, t, r, b) : Rect.zero;
  }

  /// The mesh's grid lines, for seeing how it bends.
  Path meshPath({double? spacing}) {
    final step = (spacing ?? meshSpacing) * 2;
    final path = Path();
    for (var i = 0; i < text.units.length; i++) {
      if (text.units[i].ink.isEmpty) continue;
      final (xs, ys) = _grid(i, step);
      for (final y in ys) {
        for (var c = 0; c < xs.length; c++) {
          final o = map(i, xs[c], y);
          c == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
      }
      for (final x in xs) {
        for (var r = 0; r < ys.length; r++) {
          final o = map(i, x, ys[r]);
          r == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
      }
    }
    return path;
  }
}

/// A join whose sides land [delta] apart along the joining rows' curve, from [from] along it, bridged in the flat rows
/// [top] to [bottom].
class _Bridge {
  _Bridge(this.pair, this.from, this.delta, this.top, this.bottom);
  final UnitPair pair;
  final double from, delta, top, bottom;
}

/// A join's squeeze: across [from]..[to] in the flat run, the joining rows gain [delta] of length (less than nothing).
class _Ramp {
  _Ramp(this.from, this.to, this.delta);
  final double from, to, delta;

  /// How far across the stretch [x] is, from 0 to 1.
  double at(double x) => to > from ? ((x - from) / (to - from)).clamp(0.0, 1.0) : (x < from ? 0 : 1);
}

/// A join whose sides' copies of the boundary [x], from [top] to [bottom], didn't land where they should: [left] and
/// [right] hold, at even steps down it, how far each side's copy must move (x, y pairs).
class _Seam {
  _Seam(this.x, this.top, this.bottom, this.left, this.right, this.reach);
  final double x, top, bottom, reach;
  final Float64List left, right;

  /// Moves the point at the flat ([px], [py]) of one side of the join by that side's move at the nearest point of the
  /// boundary, fading to nothing [reach] away.
  void pull(double px, double py, bool isLeft, Float64List out) {
    final cy = py.clamp(top, bottom);
    final ex = px - x, ey = py - cy;
    final d = math.sqrt(ex * ex + ey * ey);
    if (d >= reach) return;
    final t = d / reach;
    final f = 1 - t * t * (3 - 2 * t);
    final moves = isLeft ? left : right;
    final rows = moves.length ~/ 2;
    final at = bottom > top ? (cy - top) / (bottom - top) * (rows - 1) : 0.0;
    final k = at.floor().clamp(0, rows - 2), g = at - k;
    out[0] += f * (moves[2 * k] + g * (moves[2 * k + 2] - moves[2 * k]));
    out[1] += f * (moves[2 * k + 1] + g * (moves[2 * k + 3] - moves[2 * k + 1]));
  }
}

extension on Path {
  void addPolygonLoops(List<Float64List> loops) {
    for (final loop in loops) {
      if (loop.length < 6) continue;
      moveTo(loop[0], loop[1]);
      for (var k = 2; k < loop.length; k += 2) {
        lineTo(loop[k], loop[k + 1]);
      }
      close();
    }
  }
}
