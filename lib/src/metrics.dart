import 'dart:math' as math;

import 'placement.dart';

/// How well a placement keeps joins closed and letters in shape. Lengths are logical pixels at the text's size.
class TextOnPathMetrics {
  const TextOnPathMetrics({
    required this.gapArea,
    required this.overlapArea,
    required this.joins,
    required this.openJoins,
    required this.distortion,
    required this.worstDistortion,
  });

  /// Measures [placement] as drawn: through its mesh, not its formula.
  ///
  /// Joins: wherever a stroke runs from one cluster into the next, each cluster carries its own copy of the boundary
  /// between them. Where the two copies land apart, the crack between them is a gap; where they cross, the letters
  /// overlap. Both are areas, in square pixels, summed over every join.
  ///
  /// Distortion: each cluster's ink is compared with the closest rigid placement of the same letter (the best
  /// rotation and shift, by least squares). The root mean square distance, over all the ink, is how far the letters
  /// were bent out of shape, in pixels.
  factory TextOnPathMetrics.of(TextOnPathPlacement placement) {
    final text = placement.text;
    final step = 1 / text.scale;
    var gap = 0.0, overlap = 0.0, joins = 0, open = 0;
    for (final p in text.neighbours) {
      if (!p.joins) continue;
      joins++;
      var widest = 0.0;
      for (final (y0, y1) in p.crossing) {
        for (var y = y0 + step / 2; y < y1; y += step) {
          // Along the text, from the left cluster's side of the join to the right one's.
          final t = (placement.rendered(p.left, p.x + 0.5, y) - placement.rendered(p.left, p.x - 0.5, y)) +
              (placement.rendered(p.right, p.x + 0.5, y) - placement.rendered(p.right, p.x - 0.5, y));
          for (final (a, b) in placement.joinCopies(p, y)) {
            final along = ((b - a).dx * t.dx + (b - a).dy * t.dy) / t.distance;
            widest = math.max(widest, along.abs());
            if (along > 0) {
              gap += along * step;
            } else {
              overlap -= along * step;
            }
          }
        }
      }
      if (widest > 0.5) open++;
    }

    var squared = 0.0, weight = 0.0, worst = 0.0;
    for (var i = 0; i < text.units.length; i++) {
      final samples = text.inkSamples(text.units[i], spacing: 0.75).toList();
      if (samples.isEmpty) continue;
      final mapped = [for (final (x, y, _) in samples) placement.rendered(i, x, y)];
      // Centroids.
      var w = 0.0, px = 0.0, py = 0.0, qx = 0.0, qy = 0.0;
      for (var k = 0; k < samples.length; k++) {
        final (x, y, a) = samples[k];
        w += a;
        px += a * x;
        py += a * y;
        qx += a * mapped[k].dx;
        qy += a * mapped[k].dy;
      }
      px /= w;
      py /= w;
      qx /= w;
      qy /= w;
      // The best rotation (2D Kabsch).
      var dot = 0.0, cross = 0.0;
      for (var k = 0; k < samples.length; k++) {
        final (x, y, a) = samples[k];
        final ax = x - px, ay = y - py, bx = mapped[k].dx - qx, by = mapped[k].dy - qy;
        dot += a * (ax * bx + ay * by);
        cross += a * (ax * by - ay * bx);
      }
      final angle = math.atan2(cross, dot);
      final c = math.cos(angle), s = math.sin(angle);
      var unit = 0.0;
      for (var k = 0; k < samples.length; k++) {
        final (x, y, a) = samples[k];
        final ax = x - px, ay = y - py;
        final rx = mapped[k].dx - qx - (c * ax - s * ay), ry = mapped[k].dy - qy - (s * ax + c * ay);
        unit += a * (rx * rx + ry * ry);
      }
      squared += unit;
      weight += w;
      worst = math.max(worst, math.sqrt(unit / w));
    }

    return TextOnPathMetrics(
      gapArea: gap,
      overlapArea: overlap,
      joins: joins,
      openJoins: open,
      distortion: weight > 0 ? math.sqrt(squared / weight) : 0,
      worstDistortion: worst,
    );
  }

  /// The area, in square pixels, where joined letters pull apart.
  final double gapArea;

  /// The area, in square pixels, where joined letters push into each other.
  final double overlapArea;

  /// Gaps and overlaps together.
  double get joinArea => gapArea + overlapArea;

  /// How many joins were measured.
  final int joins;

  /// How many of them visibly open or overlap: their two sides more than half a pixel apart along the text.
  final int openJoins;

  /// How far, in pixels, ink moved from where a rigid letter would put it (root mean square over all the ink).
  final double distortion;

  /// The same for the worst cluster.
  final double worstDistortion;

  @override
  String toString() => 'joins ${joinArea.toStringAsFixed(1)} px² (gap ${gapArea.toStringAsFixed(1)}, overlap '
      '${overlapArea.toStringAsFixed(1)}, $joins joins) · distortion ${distortion.toStringAsFixed(2)} px '
      '(worst ${worstDistortion.toStringAsFixed(2)})';
}
