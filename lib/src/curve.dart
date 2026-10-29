import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A curve to lay text along: any [Path], or a circular arc for a seal.
///
/// It's kept as samples a pixel apart, by arc length, each with a unit tangent and the signed curvature there, so text
/// can be placed at any distance along it. Text stands on the curve's left: on a clockwise circle it faces out, on an
/// anticlockwise one it faces in.
class PathCurve {
  PathCurve._(this._track);

  /// The first contour of [path].
  factory PathCurve.fromPath(Path path, {double spacing = 1}) {
    // Skia flattens curves to within half a pixel. Measuring a magnified copy keeps the samples on the true curve, so
    // the tangents and curvature come out smooth.
    const zoom = 16.0;
    final big = path.transform(Float64List.fromList([zoom, 0, 0, 0, 0, zoom, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    final metric = big.computeMetrics().first;
    final n = math.max(4, (metric.length / zoom / spacing).ceil() + 1);
    final xs = Float64List(n), ys = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = metric.getTangentForOffset(metric.length * i / (n - 1))!;
      xs[i] = t.position.dx / zoom;
      ys[i] = t.position.dy / zoom;
    }
    return PathCurve._(CurveTrack.fromPoints(xs, ys, closed: metric.isClosed));
  }

  /// A circular arc. Angles are in radians, clockwise from the positive x axis, as on a canvas.
  ///
  /// A positive [sweepAngle] runs clockwise, so the text faces out; a negative one runs anticlockwise and the text faces
  /// in, as along the bottom of a seal. A full turn is a closed curve: text wraps round it.
  factory PathCurve.arc(
    Offset center,
    double radius, {
    double startAngle = math.pi / 2,
    double sweepAngle = 2 * math.pi,
    double spacing = 1,
  }) {
    final dir = sweepAngle.sign;
    final length = radius * sweepAngle.abs();
    final n = math.max(4, (length / spacing).ceil() + 1);
    final s = Float64List(n), x = Float64List(n), y = Float64List(n);
    final tx = Float64List(n), ty = Float64List(n), k = Float64List(n);
    for (var i = 0; i < n; i++) {
      final a = startAngle + sweepAngle * i / (n - 1);
      s[i] = length * i / (n - 1);
      x[i] = center.dx + radius * math.cos(a);
      y[i] = center.dy + radius * math.sin(a);
      tx[i] = -dir * math.sin(a);
      ty[i] = dir * math.cos(a);
      k[i] = dir / radius;
    }
    return PathCurve._(CurveTrack(s, x, y, tx, ty, k, closed: sweepAngle.abs() >= 2 * math.pi - 1e-9));
  }

  final CurveTrack _track;

  /// The curve's length.
  double get length => _track.length;

  /// Whether the curve closes on itself, so text wraps round it.
  bool get closed => _track.closed;

  /// The point at [distance] along the curve. On a closed curve the distance wraps; on an open one, the curve carries
  /// on straight past its ends.
  Offset pointAt(double distance) {
    final out = Float64List(5);
    _track.eval(distance, out);
    return Offset(out[0], out[1]);
  }

  /// The unit tangent at [distance] along the curve.
  Offset tangentAt(double distance) {
    final out = Float64List(5);
    _track.eval(distance, out);
    return Offset(out[2], out[3]);
  }

  /// The curvature at [distance]: one over the radius of the bend, positive where the curve turns clockwise (away from
  /// the side the text stands on).
  double curvatureAt(double distance) {
    final out = Float64List(5);
    _track.eval(distance, out);
    return out[4];
  }

  /// The curve as a [Path], for drawing it.
  Path toPath() {
    final path = Path()..moveTo(_track.x[0], _track.y[0]);
    for (var i = 1; i < _track.x.length; i++) {
      path.lineTo(_track.x[i], _track.y[i]);
    }
    if (closed) path.close();
    return path;
  }
}

/// Lets the rest of the package reach a curve's samples.
CurveTrack trackOf(PathCurve curve) => curve._track;

/// A curve as samples by arc length; internal to the package. [eval] fills `x, y, tx, ty, curvature` for any distance
/// along it.
class CurveTrack {
  CurveTrack(this.s, this.x, this.y, this.tx, this.ty, this.k, {required this.closed});

  factory CurveTrack.fromPoints(Float64List xs, Float64List ys, {required bool closed}) {
    final n = xs.length;
    final s = Float64List(n);
    for (var i = 1; i < n; i++) {
      s[i] = s[i - 1] + math.sqrt(math.pow(xs[i] - xs[i - 1], 2) + math.pow(ys[i] - ys[i - 1], 2));
    }
    // Tangents by central differences a few samples wide; on a closed curve they wrap round the joint.
    int at(int i) {
      if (!closed) return i.clamp(0, n - 1);
      // The last sample repeats the first.
      return ((i % (n - 1)) + (n - 1)) % (n - 1);
    }

    const w = 2;
    final tx = Float64List(n), ty = Float64List(n), angle = Float64List(n);
    for (var i = 0; i < n; i++) {
      final a = at(i - w), b = at(i + w);
      var dx = xs[b] - xs[a], dy = ys[b] - ys[a];
      if (dx == 0 && dy == 0) {
        dx = 1;
      }
      final len = math.sqrt(dx * dx + dy * dy);
      tx[i] = dx / len;
      ty[i] = dy / len;
      angle[i] = math.atan2(ty[i], tx[i]);
    }
    // Curvature from the turn of the tangent, then smoothed a little.
    final raw = Float64List(n), k = Float64List(n);
    for (var i = 0; i < n; i++) {
      final a = at(i - w), b = at(i + w);
      var turn = angle[b] - angle[a];
      while (turn > math.pi) {
        turn -= 2 * math.pi;
      }
      while (turn < -math.pi) {
        turn += 2 * math.pi;
      }
      final span = closed ? (2 * w) * (s[n - 1] / (n - 1)) : (s[b] - s[a]);
      raw[i] = span > 0 ? turn / span : 0;
    }
    const r = 3;
    for (var i = 0; i < n; i++) {
      var sum = 0.0;
      for (var j = -r; j <= r; j++) {
        sum += raw[at(i + j)];
      }
      k[i] = sum / (2 * r + 1);
    }
    return CurveTrack(s, xs, ys, tx, ty, k, closed: closed);
  }

  final Float64List s, x, y, tx, ty, k;
  final bool closed;

  double get length => s[s.length - 1];

  /// The track offset sideways by [h], onto the side the text stands on, measured by its own arc length. Its samples
  /// line up one to one with this track's.
  CurveTrack offset(double h) {
    final n = s.length;
    final ox = Float64List(n), oy = Float64List(n), os = Float64List(n), ok = Float64List(n);
    for (var i = 0; i < n; i++) {
      // The text's up is the tangent turned a quarter anticlockwise: (ty, -tx) on a canvas, whose y runs down.
      ox[i] = x[i] + h * ty[i];
      oy[i] = y[i] - h * tx[i];
      final stretch = 1 + k[i] * h;
      ok[i] = stretch.abs() > 1e-6 ? k[i] / stretch : 0;
      if (i > 0) {
        os[i] = os[i - 1] + math.sqrt(math.pow(ox[i] - ox[i - 1], 2) + math.pow(oy[i] - oy[i - 1], 2));
      }
    }
    return CurveTrack(os, ox, oy, Float64List.fromList(tx), Float64List.fromList(ty), ok, closed: closed);
  }

  /// The distance along [other], a track sampled one to one with this one, at the sample matching [distance] here.
  double mapTo(CurveTrack other, double distance) {
    final (i, f) = _locate(distance);
    final base = closed ? (distance / length).floorToDouble() * other.length : 0.0;
    return base + other.s[i] + f * (other.s[i + 1] - other.s[i]) + (_overrun(distance));
  }

  double _overrun(double distance) {
    if (closed) return 0;
    if (distance < 0) return distance;
    if (distance > length) return distance - length;
    return 0;
  }

  (int, double) _locate(double distance) {
    final n = s.length;
    var d = distance;
    if (closed) {
      d = d % length;
      if (d < 0) d += length;
    } else {
      d = d.clamp(0.0, length);
    }
    var lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (s[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = s[hi] - s[lo];
    return (lo, span > 0 ? (d - s[lo]) / span : 0.0);
  }

  /// Writes `x, y, tx, ty, curvature` at [distance] into [out].
  void eval(double distance, Float64List out) {
    final (i, f) = _locate(distance);
    var px = x[i] + f * (x[i + 1] - x[i]);
    var py = y[i] + f * (y[i + 1] - y[i]);
    var ux = tx[i] + f * (tx[i + 1] - tx[i]);
    var uy = ty[i] + f * (ty[i + 1] - ty[i]);
    final len = math.sqrt(ux * ux + uy * uy);
    ux /= len;
    uy /= len;
    final over = _overrun(distance);
    if (over != 0) {
      // Past an open end: carry on straight.
      px += over * ux;
      py += over * uy;
    }
    out[0] = px;
    out[1] = py;
    out[2] = ux;
    out[3] = uy;
    out[4] = over != 0 ? 0 : k[i] + f * (k[i + 1] - k[i]);
  }
}
