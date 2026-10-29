import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

import 'panel.dart';
import 'samples.dart';

/// One phrase, large, on a circle you bend: turned cluster by cluster beside text_on_path, a loupe on the join that
/// opens widest, and how many joins are open.
class BendPage extends StatefulWidget {
  const BendPage({super.key});

  @override
  State<BendPage> createState() => _BendPageState();
}

class _BendPageState extends State<BendPage> with SingleTickerProviderStateMixin {
  Sample _sample = samples[3];
  int _phrase = 0;
  double _bend = 0.8;
  late final AnimationController _animation = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..addListener(() => setState(() => _bend = Curves.easeInOut.transform(_animation.value)));

  // A denser atlas for the loupes, drawn once a phrase is shaped.
  ShapedText? _forLoupe;
  TextAtlas? _loupeAtlas;
  // The join the loupes watch: the one rigid placement opens widest at the tightest bend.
  (UnitPair, double)? _watched;
  // Measured once the bend settles.
  final _distortion = <TextOnPathMode, double>{};
  Timer? _settle;

  static const _fontSize = 46.0, _zoom = 3.2;
  static const _modes = [TextOnPathMode.rigid, TextOnPathMode.joined];

  @override
  void dispose() {
    _animation.dispose();
    _settle?.cancel();
    _loupeAtlas?.dispose();
    super.dispose();
  }

  double _radius() => _fontSize / lerpDouble(1 / 30, 1 / 2.2, _bend)!;

  PathCurve _curve(Size size) {
    final top = Offset(size.width / 2, size.height * 0.34);
    return PathCurve.arc(top + Offset(0, _radius()), _radius());
  }

  void _prepare(ShapedText shaped) {
    if (_forLoupe == shaped) return;
    _forLoupe = shaped;
    _watched = worstJoin(
      TextOnPathPlacement(shaped, PathCurve.arc(Offset.zero, 2.2 * _fontSize), mode: TextOnPathMode.rigid),
    );
    final ratio = MediaQuery.devicePixelRatioOf(context);
    shaped.drawAtlas(2 * ratio * _zoom).then((atlas) {
      if (!mounted || _forLoupe != shaped) {
        atlas.dispose();
        return;
      }
      setState(() {
        _loupeAtlas?.dispose();
        _loupeAtlas = atlas;
      });
    });
  }

  void _measureLater(ShapedText shaped, Size size) {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _animation.isAnimating) return;
      final curve = _curve(size);
      setState(() {
        for (final mode in _modes) {
          _distortion[mode] = TextOnPathMetrics.of(TextOnPathPlacement(shaped, curve, mode: mode)).distortion;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final (text, meaning) = _sample.phrases[_phrase];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in samples)
                ChoiceChip(
                  label: Text(s.name),
                  selected: s == _sample,
                  onSelected: (_) => setState(() {
                    _sample = s;
                    _phrase = 0;
                    _distortion.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (i, (p, _)) in _sample.phrases.indexed)
                ChoiceChip(
                  label: Text(p, style: _sample.style(15)),
                  selected: i == _phrase,
                  onSelected: (_) => setState(() {
                    _phrase = i;
                    _distortion.clear();
                  }),
                ),
              if (meaning.isNotEmpty) Text('“$meaning”', style: const TextStyle(fontSize: 12.5, color: muted)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Bend', style: TextStyle(fontSize: 13, color: muted)),
              SizedBox(
                width: 320,
                child: Slider(
                  value: _bend,
                  onChanged: (v) {
                    _animation.stop();
                    setState(() => _bend = v);
                  },
                ),
              ),
              Switch(
                value: _animation.isAnimating,
                onChanged: (on) => setState(() {
                  if (on) {
                    _animation
                      ..value = _bend
                      ..repeat(reverse: true);
                  } else {
                    _animation.stop();
                  }
                }),
              ),
              const Text('Bend it for me', style: TextStyle(fontSize: 13, color: ink)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Shaped(
              text: text,
              style: _sample.style(_fontSize),
              builder: (context, shaped) => LayoutBuilder(
                builder: (context, constraints) {
                  final panel = Size((constraints.maxWidth - 16) / 2, constraints.maxHeight);
                  final area = Size(panel.width, panel.height - 64);
                  if (shaped != null) {
                    _prepare(shaped);
                    if (!_animation.isAnimating) _measureLater(shaped, area);
                  }
                  final curve = _curve(area);
                  final watched = _watched;
                  return Row(
                    children: [
                      for (final (i, mode) in _modes.indexed) ...[
                        if (i > 0) const SizedBox(width: 16),
                        _panel(shaped, mode, curve, panel, area, watched),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(
    ShapedText? shaped,
    TextOnPathMode mode,
    PathCurve curve,
    Size panel,
    Size area,
    (UnitPair, double)? watched,
  ) {
    final placement = shaped == null ? null : TextOnPathPlacement(shaped, curve, mode: mode);
    final joins = shaped == null ? 0 : shaped.neighbours.where((p) => p.joins).length;
    final open = placement == null ? 0 : openJoins(placement);
    final distortion = _distortion[mode];
    final title = mode == TextOnPathMode.rigid ? 'Turned cluster by cluster' : 'text_on_path';
    return SizedBox.fromSize(
      size: panel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: modeColor(mode)),
              ),
            ),
            SizedBox.fromSize(
              size: area,
              child: shaped == null
                  ? null
                  : CustomPaint(
                      painter: PlacementPainter(
                        shaped: shaped,
                        curve: curve,
                        mode: mode,
                        loupe: watched == null
                            ? null
                            : Loupe(
                                watched.$1,
                                watched.$2,
                                Offset(area.width - 84, area.height - 84),
                                zoom: _zoom,
                                radius: 72,
                              ),
                        loupeAtlas: _loupeAtlas,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$open of $joins joins open',
                      style: TextStyle(fontWeight: FontWeight.w700, color: open > 0 ? rigidColor : joinedColor),
                    ),
                    TextSpan(
                      text: distortion == null
                          ? ''
                          : ' · letters ${distortion < 0.005 ? 'unbent' : 'bent ${distortion.toStringAsFixed(2)} px'}',
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13.5, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
