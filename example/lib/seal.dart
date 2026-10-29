import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

import 'panel.dart';
import 'samples.dart';

const sealRed = Color(0xff9c1d15);

/// Each phrase said twice round a whole ring and fitted to it, as on a seal: kashida for Arabic and Persian, tracking
/// for Hindi and Bengali, word spacing for Urdu and the Latin script hand. Rigid per-glyph placement beside joined.
class SealPage extends StatelessWidget {
  const SealPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [for (final s in samples) _SealCard(sample: s)],
        ),
      ],
    );
  }
}

class _SealCard extends StatelessWidget {
  const _SealCard({required this.sample});

  final Sample sample;

  static const sealSize = 250.0;

  @override
  Widget build(BuildContext context) {
    final phrase = '${sample.text}  ${sample.text}  ';
    // A font size that makes the phrase go about 86% of the way round a ring that fits the seal, the ink's reach
    // above the baseline (tall in Nastaliq) inside it.
    final probe = TextPainter(
      text: TextSpan(text: phrase, style: sample.style(100)),
      textDirection: TextDirection.ltr,
    )..layout();
    final perPixel = probe.width / 100;
    final above = probe.computeLineMetrics().first.ascent / 100 + 0.25;
    probe.dispose();
    final size = 0.86 * math.pi * sealSize / (perPixel + 0.86 * 2 * math.pi * above);

    return Container(
      width: 2 * sealSize + 3 * 14,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(sample.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(width: 8),
              Text(
                'fitted by ${sample.fit.name == 'spacing' ? 'word spacing' : sample.fit.name}',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Shaped(
            text: phrase,
            style: sample.style(size, color: sealRed),
            builder: (context, shaped) => Row(
              children: [
                for (final mode in [TextOnPathMode.rigid, TextOnPathMode.joined]) ...[
                  if (mode == TextOnPathMode.joined) const SizedBox(width: 14),
                  _Seal(shaped: shaped, mode: mode, fit: sample.fit),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Seal extends StatefulWidget {
  const _Seal({required this.shaped, required this.mode, required this.fit});

  final ShapedText? shaped;
  final TextOnPathMode mode;
  final TextOnPathFit fit;

  @override
  State<_Seal> createState() => _SealState();
}

class _SealState extends State<_Seal> {
  TextOnPathMetrics? _metrics;
  ShapedText? _measured;

  @override
  Widget build(BuildContext context) {
    const s = _SealCard.sealSize;
    final shaped = widget.shaped;
    PathCurve? ring;
    double inner = 0, outer = 0;
    if (shaped != null) {
      // The ink's reach above and below the baseline sets the rings either side of the text.
      var up = 0.0, down = 0.0;
      for (final u in shaped.units) {
        up = math.max(up, shaped.baseline - u.ink.top);
        down = math.max(down, u.ink.bottom - shaped.baseline);
      }
      final gap = 0.18 * shaped.fontSize;
      final r = s / 2 - up - gap - 4;
      ring = PathCurve.arc(const Offset(s / 2, s / 2), r);
      outer = r + up + gap;
      inner = r - down - gap;
      if (_measured != shaped) {
        _measured = shaped;
        final placement = TextOnPathPlacement(
          shaped,
          ring,
          mode: widget.mode,
          fit: widget.fit,
          fitLength: ring.length - shaped.fontSize,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _measured == shaped) setState(() => _metrics = TextOnPathMetrics.of(placement));
        });
      }
    }
    return SizedBox(
      width: s,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: s,
            child: shaped == null || ring == null
                ? null
                : CustomPaint(
                    painter: _RingsPainter(inner, outer),
                    foregroundPainter: PlacementPainter(
                      shaped: shaped,
                      curve: ring,
                      mode: widget.mode,
                      fit: widget.fit,
                      fitLength: ring.length - shaped.fontSize,
                      showCurve: false,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          PanelCaption(mode: widget.mode, metrics: _metrics),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.inner, this.outer);

  final double inner, outer;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = sealRed;
    canvas.drawCircle(c, outer, p..strokeWidth = 2.4);
    canvas.drawCircle(c, outer + 4, p..strokeWidth = 0.8);
    canvas.drawCircle(c, inner, p..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.inner != inner || old.outer != outer;
}
