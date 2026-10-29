import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

import 'panel.dart';
import 'samples.dart';

/// The compare page's scroll position, so a capture can reach the lower rows.
final compareScroll = ScrollController();

/// Every sample on a circle and on an S-curve: rigid per-glyph placement beside joined placement, each measured.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  double bend = 0.62, size = 32, stretch = 0;
  bool mesh = false, warp = false, live = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Controls(
          bend: bend,
          size: size,
          stretch: stretch,
          mesh: mesh,
          warp: warp,
          onBend: (v) => setState(() => bend = v),
          onSize: (v) => setState(() => size = v),
          onStretch: (v) => setState(() => stretch = v),
          onMesh: (v) => setState(() => mesh = v),
          onWarp: (v) => setState(() => warp = v),
          onDragging: (v) => setState(() => live = v),
        ),
        Expanded(
          child: ListView.separated(
            controller: compareScroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: samples.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, i) => SampleRow(
              sample: samples[i],
              bend: bend,
              size: size,
              stretch: stretch,
              mesh: mesh,
              warp: warp,
              live: live,
            ),
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.bend,
    required this.size,
    required this.stretch,
    required this.mesh,
    required this.warp,
    required this.onBend,
    required this.onSize,
    required this.onStretch,
    required this.onMesh,
    required this.onWarp,
    required this.onDragging,
  });

  final double bend, size, stretch;
  final bool mesh, warp;
  final ValueChanged<double> onBend, onSize, onStretch;
  final ValueChanged<bool> onMesh, onWarp, onDragging;

  @override
  Widget build(BuildContext context) {
    Widget slider(String label, String value, double v, double min, double max, ValueChanged<double> on) => SizedBox(
          width: 250,
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(label, style: const TextStyle(fontSize: 12.5, color: muted)),
              ),
              Expanded(
                child: Slider(
                  value: v,
                  min: min,
                  max: max,
                  onChangeStart: (_) => onDragging(true),
                  onChangeEnd: (_) => onDragging(false),
                  onChanged: on,
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(value, style: const TextStyle(fontSize: 12.5, color: ink)),
              ),
            ],
          ),
        );
    Widget toggle(String label, bool v, ValueChanged<bool> on) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: v, onChanged: on),
            Text(label, style: const TextStyle(fontSize: 12.5, color: ink)),
            const SizedBox(width: 14),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          slider('Bend', bend < 0.34 ? 'gentle' : (bend < 0.67 ? 'medium' : 'tight'), bend, 0, 1, onBend),
          slider('Size', '${size.round()} px', size, 18, 56, onSize),
          slider('Fill', stretch == 0 ? 'natural' : '+${(stretch * 100).round()}%', stretch, 0, 0.6, onStretch),
          toggle('Mesh', mesh, onMesh),
          toggle('Plain warp', warp, onWarp),
        ],
      ),
    );
  }
}

/// One sample: its name and phrase, then each curve in each mode.
class SampleRow extends StatefulWidget {
  const SampleRow({
    super.key,
    required this.sample,
    required this.bend,
    required this.size,
    required this.stretch,
    required this.mesh,
    required this.warp,
    required this.live,
  });

  final Sample sample;
  final double bend, size, stretch;
  final bool mesh, warp, live;

  @override
  State<SampleRow> createState() => _SampleRowState();
}

class _SampleRowState extends State<SampleRow> {
  final _metrics = <String, TextOnPathMetrics>{};
  Object? _measuredFor;

  @override
  Widget build(BuildContext context) {
    final s = widget.sample;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: 2),
                  Text(s.font, style: const TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 10),
                  Text(s.text, style: s.style(19)),
                  if (s.meaning.isNotEmpty) Text('“${s.meaning}”', style: const TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 10),
                  Text('Joins ${s.joinsOn}.', style: const TextStyle(fontSize: 12, color: muted, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Shaped(
                // Denser than the screen needs, so the loupes stay crisp.
                oversample: 3,
                text: s.text,
                style: s.style(widget.size),
                builder: (context, shaped) => LayoutBuilder(
                  builder: (context, constraints) => _panels(shaped, constraints.maxWidth),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panels(ShapedText? shaped, double width) {
    final modes = [TextOnPathMode.rigid, if (widget.warp) TextOnPathMode.warp, TextOnPathMode.joined];
    const gap = 10.0, curveGap = 22.0;
    final count = 2 * modes.length;
    final w = (width - (count - 2) * gap - curveGap) / count;
    final panel = Size(w, (w * 0.7).clamp(160.0, 290.0));
    final area = Size(panel.width, panel.height - 20);
    final curves = {
      'circle': circleIn(area, widget.bend, widget.size),
      'S-curve': sCurveIn(area, widget.bend, widget.size),
    };
    final fit = widget.stretch > 0 ? widget.sample.fit : TextOnPathFit.none;
    final fitLength = shaped == null ? null : shaped.width * (1 + widget.stretch);

    // Measure once the controls settle: each placement is measured through its mesh, which takes a moment.
    final key = (shaped, widget.bend, widget.stretch, widget.warp, panel);
    if (shaped != null && !widget.live && key != _measuredFor) {
      _measuredFor = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _measuredFor != key) return;
        final results = <String, TextOnPathMetrics>{};
        for (final MapEntry(key: name, value: curve) in curves.entries) {
          for (final mode in modes) {
            results['$name $mode'] = TextOnPathMetrics.of(
              TextOnPathPlacement(shaped, curve, mode: mode, fit: fit, fitLength: fitLength),
            );
          }
        }
        setState(() => _metrics
          ..clear()
          ..addAll(results));
      });
    }

    // Each curve's text is centred in its panels, and gets a loupe onto the join rigid placement opens widest.
    final shifts = <String, Offset>{}, loupes = <String, Loupe?>{};
    if (shaped != null) {
      for (final MapEntry(key: name, value: curve) in curves.entries) {
        final rigid = TextOnPathPlacement(shaped, curve, mode: TextOnPathMode.rigid, fit: fit, fitLength: fitLength);
        final box = placedBounds(rigid);
        final shift = area.center(Offset.zero) - box.center;
        shifts[name] = shift;
        final worst = worstJoin(rigid);
        if (worst != null) {
          // The corner furthest from the text.
          const r = 40.0, inset = r + 5;
          final corners = [
            Offset(inset, inset),
            Offset(area.width - inset, inset),
            Offset(inset, area.height - inset),
            Offset(area.width - inset, area.height - inset),
          ];
          final anchors = [
            for (var i = 0; i < shaped.units.length; i++)
              rigid.map(i, shaped.units[i].anchor, shaped.units[i].ink.center.dy) + shift,
          ];
          double clearance(Offset c) =>
              anchors.fold(double.infinity, (m, a) => m < (a - c).distance ? m : (a - c).distance);
          final corner = corners.reduce((a, b) => clearance(a) >= clearance(b) ? a : b);
          loupes[name] = Loupe(worst.$1, worst.$2, corner, radius: r);
        }
      }
    }

    final children = <Widget>[];
    for (final MapEntry(key: name, value: curve) in curves.entries) {
      if (children.isNotEmpty) children.add(const SizedBox(width: curveGap));
      for (final (i, mode) in modes.indexed) {
        if (i > 0) children.add(const SizedBox(width: gap));
        children.add(
          SizedBox(
            width: panel.width,
            child: DecoratedBox(
              decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
                    child: Text(name, style: const TextStyle(fontSize: 11, color: muted, letterSpacing: 0.3)),
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
                              fit: fit,
                              fitLength: fitLength,
                              showMesh: widget.mesh,
                              shift: shifts[name] ?? Offset.zero,
                              loupe: loupes[name],
                            ),
                          ),
                  ),
                  Opacity(
                    opacity: widget.live ? 0.35 : 1,
                    child: PanelCaption(mode: mode, metrics: _metrics['$name $mode']),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
