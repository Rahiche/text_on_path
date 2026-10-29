import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

import 'panel.dart';
import 'samples.dart';

enum _Shape { circle, sCurve, freehand }

/// Your own text on your own curve: a circle to size, an S to pull about by its handles, or a line drawn by hand.
class DrawPage extends StatefulWidget {
  const DrawPage({super.key});

  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  final _text = TextEditingController(text: samples.first.text);
  String _family = samples.first.family;
  TextOnPathMode _mode = TextOnPathMode.joined;
  _Shape _shape = _Shape.sCurve;
  bool _fill = false;
  double _size = 44;

  // Everything in fractions of the canvas, so it keeps its shape as the window does.
  double _radius = 0.3;
  final _handles = [
    const Offset(0.08, 0.6),
    const Offset(0.36, 0.08),
    const Offset(0.64, 0.95),
    const Offset(0.92, 0.42),
  ];
  List<Offset> _stroke = const [];
  List<Offset>? _drawing;
  int? _dragged;

  static const _fonts = [
    ('Naskh', 'Noto Naskh Arabic'),
    ('Nastaliq', 'Noto Nastaliq Urdu'),
    ('Deva', 'Noto Sans Devanagari'),
    ('Beng', 'Noto Sans Bengali'),
    ('Dancing', 'Dancing Script'),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  PathCurve? _curve(Size size) {
    Offset at(Offset f) => Offset(f.dx * size.width, f.dy * size.height);
    switch (_shape) {
      case _Shape.circle:
        final r = _radius * math.min(size.width, size.height);
        return PathCurve.arc(size.center(Offset.zero) + Offset(0, r * 0.35), math.max(r, 20));
      case _Shape.sCurve:
        final p = _handles.map(at).toList();
        return PathCurve.fromPath(
          Path()
            ..moveTo(p[0].dx, p[0].dy)
            ..cubicTo(p[1].dx, p[1].dy, p[2].dx, p[2].dy, p[3].dx, p[3].dy),
        );
      case _Shape.freehand:
        final points = (_drawing ?? _stroke).map(at).toList();
        if (points.length < 2) return null;
        return PathCurve.fromPath(_smooth(points));
    }
  }

  /// A Catmull-Rom spline through [points], as cubic Béziers.
  static Path _smooth(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i + 1 < points.length; i++) {
      final p0 = points[math.max(0, i - 1)], p1 = points[i], p2 = points[i + 1];
      final p3 = points[math.min(points.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _start(Offset p, Size size) {
    final f = Offset(p.dx / size.width, p.dy / size.height);
    switch (_shape) {
      case _Shape.circle:
        _update(p, size);
      case _Shape.sCurve:
        var best = 0;
        for (var i = 1; i < 4; i++) {
          if ((_handles[i] - f).distance < (_handles[best] - f).distance) best = i;
        }
        final near = Offset((_handles[best].dx - f.dx) * size.width, (_handles[best].dy - f.dy) * size.height);
        _dragged = near.distance < 40 ? best : null;
      case _Shape.freehand:
        setState(() => _drawing = [f]);
    }
  }

  void _update(Offset p, Size size) {
    final f = Offset((p.dx / size.width).clamp(0.0, 1.0), (p.dy / size.height).clamp(0.0, 1.0));
    setState(() {
      switch (_shape) {
        case _Shape.circle:
          final centre = size.center(Offset.zero);
          _radius = ((p - centre).distance / math.min(size.width, size.height)).clamp(0.08, 0.6);
        case _Shape.sCurve:
          final i = _dragged;
          if (i != null) _handles[i] = f;
        case _Shape.freehand:
          final last = _drawing!.last;
          if (Offset((f.dx - last.dx) * size.width, (f.dy - last.dy) * size.height).distance > 6) {
            _drawing = [..._drawing!, f];
          }
      }
    });
  }

  void _end() {
    setState(() {
      if (_drawing != null && _drawing!.length > 2) _stroke = _drawing!;
      _drawing = null;
      _dragged = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final arabicScript = _text.text.runes.any((c) => c >= 0x0600 && c <= 0x06FF);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  controller: _text,
                  style: TextStyle(fontFamily: _family, fontSize: 18),
                  decoration: const InputDecoration(labelText: 'Your text', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in samples)
                      ActionChip(
                        label: Text(s.name),
                        onPressed: () => setState(() {
                          final i = s.phrases.indexWhere((p) => p.$1 == _text.text);
                          _text.text = s.phrases[(i + 1) % s.phrases.length].$1;
                          _family = s.family;
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _family,
                items: [for (final (f, name) in _fonts) DropdownMenuItem(value: f, child: Text(name))],
                onChanged: (f) => setState(() => _family = f!),
              ),
              SegmentedButton<TextOnPathMode>(
                segments: [
                  for (final m in TextOnPathMode.values) ButtonSegment(value: m, label: Text(modeLabel(m))),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              SegmentedButton<_Shape>(
                segments: const [
                  ButtonSegment(value: _Shape.circle, label: Text('Circle')),
                  ButtonSegment(value: _Shape.sCurve, label: Text('S-curve')),
                  ButtonSegment(value: _Shape.freehand, label: Text('Draw')),
                ],
                selected: {_shape},
                onSelectionChanged: (s) => setState(() => _shape = s.first),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(value: _fill, onChanged: (v) => setState(() => _fill = v)),
                  Text(
                    'Fill the curve (${arabicScript ? 'kashida' : 'tracking'})',
                    style: const TextStyle(fontSize: 13, color: ink),
                  ),
                ],
              ),
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    const Text('Size', style: TextStyle(fontSize: 13, color: muted)),
                    Expanded(
                      child: Slider(value: _size, min: 20, max: 80, onChanged: (v) => setState(() => _size = v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            switch (_shape) {
              _Shape.circle => 'Drag to size the circle.',
              _Shape.sCurve => 'Drag the handles.',
              _Shape.freehand => 'Draw a line, and the text follows it.',
            },
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: Colors.white,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    final curve = _curve(size);
                    return GestureDetector(
                      onPanStart: (d) => _start(d.localPosition, size),
                      onPanUpdate: (d) => _update(d.localPosition, size),
                      onPanEnd: (_) => _end(),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CurvePainter(
                                curve,
                                _shape == _Shape.sCurve
                                    ? [for (final h in _handles) Offset(h.dx * size.width, h.dy * size.height)]
                                    : const [],
                              ),
                            ),
                          ),
                          if (curve != null && _text.text.trim().isNotEmpty)
                            Positioned.fill(
                              child: TextOnPath(
                                _text.text,
                                curve: curve,
                                style: TextStyle(fontFamily: _family, fontSize: _size, color: ink),
                                mode: _mode,
                                fit: _fill
                                    ? (arabicScript ? TextOnPathFit.kashida : TextOnPathFit.tracking)
                                    : TextOnPathFit.none,
                                fitLength: _fill ? curve.length * (curve.closed ? 0.97 : 1) : null,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.curve, this.handles);

  final PathCurve? curve;
  final List<Offset> handles;

  @override
  void paint(Canvas canvas, Size size) {
    final c = curve;
    if (c != null) {
      canvas.drawPath(
        c.toPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x33000000),
      );
    }
    if (handles.length == 4) {
      final guide = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = joinedColor.withValues(alpha: 0.4);
      canvas
        ..drawLine(handles[0], handles[1], guide)
        ..drawLine(handles[2], handles[3], guide);
      for (final h in handles) {
        canvas
          ..drawCircle(h, 8, Paint()..color = Colors.white)
          ..drawCircle(
            h,
            8,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = joinedColor,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
