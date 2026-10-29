import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

const paper = Color(0xfff7f3ec);
const ink = Color(0xff1d1a16);
const muted = Color(0xff7a7268);
const line = Color(0xffe4ddd1);
const rigidColor = Color(0xffa1432c);
const joinedColor = Color(0xff0f6e5c);
const warpColor = Color(0xff5a5f9e);

String modeLabel(TextOnPathMode mode) => switch (mode) {
      TextOnPathMode.rigid => 'Rigid per-glyph',
      TextOnPathMode.warp => 'Plain warp',
      TextOnPathMode.joined => 'Joined',
    };

Color modeColor(TextOnPathMode mode) => switch (mode) {
      TextOnPathMode.rigid => rigidColor,
      TextOnPathMode.warp => warpColor,
      TextOnPathMode.joined => joinedColor,
    };

/// A circle whose top carries the text, tighter as [bend] goes from 0 to 1.
PathCurve circleIn(Size size, double bend, double fontSize) {
  final r = math.min(lerpDouble(5.5, 1.8, bend)! * fontSize, 0.46 * size.width);
  final center = Offset(size.width / 2, math.max(size.height / 2, r + 1.5 * fontSize + 6));
  return PathCurve.arc(center, r);
}

/// An S across the panel, deeper as [bend] goes from 0 to 1. Built as a [Path], like any curve a caller might have.
PathCurve sCurveIn(Size size, double bend, double fontSize) {
  final m = 0.05 * size.width, w = size.width - 2 * m;
  final y = size.height / 2 + 0.3 * fontSize;
  final a = lerpDouble(0.08, 0.36, bend)! * size.width;
  return PathCurve.fromPath(
    Path()
      ..moveTo(m, y)
      ..cubicTo(m + w / 3, y - a, m + 2 * w / 3, y + a, m + w, y),
  );
}

/// Shapes [text] once (again when it or the style changes) and builds with the result. Keeps showing the last
/// result while a new one is shaped.
class Shaped extends StatefulWidget {
  const Shaped({super.key, required this.text, required this.style, this.oversample = 2, required this.builder});

  final String text;
  final TextStyle style;

  /// Atlas texels per physical pixel.
  final double oversample;
  final Widget Function(BuildContext context, ShapedText? shaped) builder;

  @override
  State<Shaped> createState() => _ShapedState();
}

class _ShapedState extends State<Shaped> {
  ShapedText? _shaped;
  Object? _for;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shape();
  }

  @override
  void didUpdateWidget(Shaped oldWidget) {
    super.didUpdateWidget(oldWidget);
    _shape();
  }

  void _shape() {
    final scale = MediaQuery.devicePixelRatioOf(context) * widget.oversample;
    final key = (widget.text, widget.style, scale);
    if (key == _for) return;
    _for = key;
    final generation = ++_generation;
    ShapedText.layout(widget.text, widget.style, scale: scale).then((shaped) {
      if (!mounted || generation != _generation) {
        shaped.dispose();
        return;
      }
      final old = _shaped;
      setState(() => _shaped = shaped);
      // Let the frame that still paints the old atlas finish first.
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    });
  }

  @override
  void dispose() {
    _shaped?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shaped);
}

/// Where the placed text's ink reaches, traced round each cluster's ink box.
Rect placedBounds(TextOnPathPlacement p) {
  Rect? box;
  for (var i = 0; i < p.text.units.length; i++) {
    final ink = p.text.units[i].ink;
    if (ink.isEmpty) continue;
    for (var k = 0; k <= 6; k++) {
      final f = k / 6;
      for (final o in [
        p.map(i, ink.left + ink.width * f, ink.top),
        p.map(i, ink.left + ink.width * f, ink.bottom),
        p.map(i, ink.left, ink.top + ink.height * f),
        p.map(i, ink.right, ink.top + ink.height * f),
      ]) {
        final r = Rect.fromPoints(o, o);
        box = box == null ? r : box.expandToInclude(r);
      }
    }
  }
  return box ?? Rect.zero;
}

/// How many of [placement]'s joins visibly open or overlap: their two sides, as drawn, more than half a pixel apart.
/// A quick count, a few rows a join, for showing live.
int openJoins(TextOnPathPlacement placement) {
  var open = 0;
  for (final p in placement.text.neighbours) {
    if (!p.joins) continue;
    var worst = 0.0;
    for (final (y0, y1) in p.crossing) {
      for (final y in [y0 + 0.5, (y0 + y1) / 2, y1 - 0.5]) {
        for (final (a, b) in placement.joinCopies(p, y)) {
          worst = math.max(worst, (b - a).distance);
        }
      }
    }
    if (worst > 0.5) open++;
  }
  return open;
}

/// The join that [rigid] placement opens widest, and the row through its middle.
(UnitPair, double)? worstJoin(TextOnPathPlacement rigid) {
  (UnitPair, double)? worst;
  var widest = 0.0;
  for (final p in rigid.text.neighbours) {
    if (!p.joins) continue;
    for (final (y0, y1) in p.crossing) {
      for (final y in [y0 + 0.5, (y0 + y1) / 2, y1 - 0.5]) {
        final d = (rigid.rendered(p.left, p.x, y) - rigid.rendered(p.right, p.x, y)).distance;
        if (d > widest) {
          widest = d;
          worst = (p, (y0 + y1) / 2);
        }
      }
    }
  }
  return worst;
}

/// A magnified circle, at [center] in the panel, onto one join.
class Loupe {
  const Loupe(this.pair, this.y, this.center, {this.zoom = 3.4, this.radius = 46});

  final UnitPair pair;
  final double y;
  final Offset center;
  final double zoom, radius;
}

/// Paints one placement of shaped text on a curve, with the curve faintly behind it, moved by [shift]; and, if
/// given, a [loupe] onto one join.
class PlacementPainter extends CustomPainter {
  PlacementPainter({
    required this.shaped,
    required this.curve,
    required this.mode,
    this.fit = TextOnPathFit.none,
    this.fitLength,
    this.showMesh = false,
    this.showCurve = true,
    this.shift = Offset.zero,
    this.loupe,
    this.loupeAtlas,
  });

  final ShapedText shaped;
  final PathCurve curve;
  final TextOnPathMode mode;
  final TextOnPathFit fit;
  final double? fitLength;
  final bool showMesh, showCurve;
  final Offset shift;
  final Loupe? loupe;

  /// A denser atlas for the loupe, so the magnified text stays sharp.
  final TextAtlas? loupeAtlas;

  TextOnPathPlacement get placement => TextOnPathPlacement(shaped, curve, mode: mode, fit: fit, fitLength: fitLength);

  void _scene(Canvas canvas, TextOnPathPlacement p, [TextAtlas? atlas]) {
    if (showCurve) {
      canvas.drawPath(
        curve.toPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x22000000),
      );
    }
    p.paint(canvas, atlas: atlas);
    if (showMesh) {
      canvas.drawPath(
        p.meshPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4
          ..color = modeColor(mode).withValues(alpha: 0.55),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final p = placement;
    canvas
      ..save()
      ..translate(shift.dx, shift.dy);
    _scene(canvas, p);
    canvas.restore();

    final l = loupe;
    if (l == null) return;
    final a = p.rendered(l.pair.left, l.pair.x, l.y), b = p.rendered(l.pair.right, l.pair.x, l.y);
    final source = (a + b) / 2 + shift;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..color = modeColor(mode).withValues(alpha: 0.8);
    canvas.drawCircle(source, l.radius / l.zoom, edge..strokeWidth = 1);
    final towards = l.center - source;
    final unit = towards / towards.distance;
    canvas.drawLine(source + unit * (l.radius / l.zoom), l.center - unit * l.radius, edge..strokeWidth = 0.8);
    canvas
      ..save()
      ..clipPath(Path()..addOval(Rect.fromCircle(center: l.center, radius: l.radius)))
      ..drawPaint(Paint()..color = Colors.white)
      ..translate(l.center.dx, l.center.dy)
      ..scale(l.zoom)
      ..translate(-source.dx + shift.dx, -source.dy + shift.dy);
    _scene(canvas, p, loupeAtlas);
    canvas.restore();
    canvas.drawCircle(l.center, l.radius, edge..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(PlacementPainter old) =>
      old.shaped != shaped ||
      old.curve != curve ||
      old.mode != mode ||
      old.fit != fit ||
      old.fitLength != fitLength ||
      old.showMesh != showMesh ||
      old.showCurve != showCurve ||
      old.shift != shift ||
      old.loupe != loupe ||
      old.loupeAtlas != loupeAtlas;
}

/// A small caption: a coloured label, and the two measurements under it.
class PanelCaption extends StatelessWidget {
  const PanelCaption({super.key, required this.mode, this.metrics});

  final TextOnPathMode mode;
  final TextOnPathMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    const numbers = TextStyle(fontSize: 11.5, color: muted, fontFeatures: [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: modeColor(mode), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                modeLabel(mode),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: modeColor(mode)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            m == null ? ' ' : 'joins ${_area(m.joinArea)} · distortion ${m.distortion.toStringAsFixed(2)} px',
            style: numbers,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  static String _area(double a) => a < 0.05 ? '0 px²' : '${a.toStringAsFixed(a < 10 ? 1 : 0)} px²';
}
