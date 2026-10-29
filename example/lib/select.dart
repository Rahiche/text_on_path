import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

import 'panel.dart';
import 'samples.dart';

/// Every script on a curve inside one [SelectionArea]: drag across it, double-click a word, long-press on a phone for
/// handles, copy. What's selected shows underneath.
class SelectPage extends StatefulWidget {
  const SelectPage({super.key});

  @override
  State<SelectPage> createState() => _SelectPageState();
}

class _SelectPageState extends State<SelectPage> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Drag across the text, double-click a word, or long-press on a phone for handles; then copy. The positions '
            'come from the straight line the text was shaped as, so right to left, clusters and words come out right.',
            style: TextStyle(fontSize: 13, color: muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SelectionArea(
              onSelectionChanged: (content) => setState(() => _selected = content?.plainText ?? ''),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100 ? 3 : (constraints.maxWidth >= 700 ? 2 : 1);
                  final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  final height = math.min(width * 0.62, 260.0);
                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final (i, s) in samples.indexed)
                          _Card(sample: s, size: Size(width, height), arc: i.isEven),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Selected: ', style: TextStyle(color: muted)),
                  TextSpan(
                    text: _selected.isEmpty ? '(nothing yet)' : _selected,
                    style: TextStyle(
                      color: _selected.isEmpty ? muted : ink,
                      fontWeight: FontWeight.w600,
                      fontFamilyFallback: const ['Naskh', 'Nastaliq', 'Deva', 'Beng', 'Dancing'],
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.sample, required this.size, required this.arc});

  final Sample sample;
  final Size size;
  final bool arc;

  @override
  Widget build(BuildContext context) {
    const fontSize = 34.0;
    final area = Size(size.width, size.height - 30);
    final curve = arc
        ? PathCurve.arc(Offset(area.width / 2, 40 + 3.4 * fontSize), 3.4 * fontSize)
        : PathCurve.fromPath(
            Path()
              ..moveTo(0.06 * area.width, area.height * 0.55)
              ..cubicTo(
                0.38 * area.width,
                area.height * 0.05,
                0.62 * area.width,
                area.height * 1.0,
                0.94 * area.width,
                area.height * 0.45,
              ),
          );
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              sample.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
            ),
          ),
          SizedBox.fromSize(
            size: area,
            child: TextOnPath(sample.text, curve: curve, style: sample.style(fontSize)),
          ),
        ],
      ),
    );
  }
}
