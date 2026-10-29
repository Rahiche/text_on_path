import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:text_on_path/text_on_path.dart';

import 'panel.dart';
import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart' as platform;
import 'samples.dart';

/// The Zoom tab's view and rendering, so a capture can set them.
final zoomView = TransformationController();
final zoomRendering = ValueNotifier(TextOnPathRendering.auto);
Size _viewSize = Size.zero;

/// Zooms the Zoom tab's view in [zoom] times on the top of the text.
void zoomInOnText(double zoom) {
  final c = _viewSize.center(Offset.zero);
  zoomView.value = Matrix4.identity()
    ..translateByDouble(c.dx, c.dy, 0, 1)
    ..scaleByDouble(zoom, zoom, 1, 1)
    ..translateByDouble(-c.dx, -c.dy + 0.45 * _ZoomPageState.fontSize, 0, 1);
}

/// One sample, magnified, drawn by the [TextOnPath] widget itself: from one atlas, which softens as the view zooms
/// in; from an atlas drawn again for the zoom; or from traced outlines. Saves the placed text as SVG or PDF.
class ZoomPage extends StatefulWidget {
  const ZoomPage({super.key});

  @override
  State<ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<ZoomPage> {
  Sample _sample = samples[3];
  TextOnPathMode _mode = TextOnPathMode.joined;
  bool _mesh = false;
  double _zoom = 1;

  static const fontSize = 56.0;

  @override
  void initState() {
    super.initState();
    zoomView.addListener(_zoomed);
    zoomRendering.addListener(_rerender);
  }

  void _zoomed() {
    final zoom = zoomView.value.getMaxScaleOnAxis();
    if (zoom != _zoom) setState(() => _zoom = zoom);
  }

  void _rerender() => setState(() {});

  @override
  void dispose() {
    zoomView.removeListener(_zoomed);
    zoomRendering.removeListener(_rerender);
    super.dispose();
  }

  PathCurve _curve(Size size) =>
      PathCurve.arc(Offset(size.width / 2, size.height / 2 + 3.4 * fontSize), 3.4 * fontSize);

  Future<void> _export(Size size, String kind) async {
    final shaped = await ShapedText.layout(_sample.text, _sample.style(fontSize));
    final outlines = await TextOutlines.trace(shaped);
    final placement = TextOnPathPlacement(shaped, _curve(size), mode: _mode);
    final name = '${_sample.name.toLowerCase().replaceAll(' ', '_')}_${_mode.name}.$kind';
    final saved = kind == 'svg'
        ? await platform.saveFile(name, utf8.encode(placement.toSvg(outlines)), 'image/svg+xml')
        : await platform.saveFile(name, placement.toPdf(outlines), 'application/pdf');
    shaped.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
  }

  @override
  Widget build(BuildContext context) {
    final rendering = zoomRendering.value;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screen = dpr * _zoom;
    final note = switch (rendering) {
      TextOnPathRendering.raster => 'one atlas of ${(2 * dpr).toStringAsFixed(0)} texels per logical pixel: '
          '${(2 / _zoom).toStringAsFixed(2)} per screen pixel${_zoom > 1.5 ? ', softer than the screen' : ''}',
      TextOnPathRendering.auto =>
        'an atlas of ${TextOnPath.atlasDensityFor(screen).toStringAsFixed(1)} texels per logical pixel, drawn again '
            'for the zoom (outlines past 16 M texels)',
      TextOnPathRendering.vector => 'traced outlines',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in samples)
                ChoiceChip(label: Text(s.name), selected: s == _sample, onSelected: (_) => setState(() => _sample = s)),
              const SizedBox(width: 8),
              SegmentedButton<TextOnPathMode>(
                segments: [
                  for (final m in [TextOnPathMode.rigid, TextOnPathMode.warp, TextOnPathMode.joined])
                    ButtonSegment(value: m, label: Text(modeLabel(m))),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(width: 8),
              SegmentedButton<TextOnPathRendering>(
                segments: const [
                  ButtonSegment(value: TextOnPathRendering.raster, label: Text('One atlas')),
                  ButtonSegment(value: TextOnPathRendering.auto, label: Text('Auto')),
                  ButtonSegment(value: TextOnPathRendering.vector, label: Text('Outlines')),
                ],
                selected: {rendering},
                onSelectionChanged: (s) => zoomRendering.value = s.first,
              ),
              const SizedBox(width: 8),
              Switch(value: _mesh, onChanged: (v) => setState(() => _mesh = v)),
              const Text('Mesh', style: TextStyle(fontSize: 13, color: ink)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Zoom ${_zoom.toStringAsFixed(1)}× · $note. Scroll or pinch to zoom.',
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                _viewSize = size;
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ColoredBox(
                        color: Colors.white,
                        child: InteractiveViewer(
                          transformationController: zoomView,
                          minScale: 0.5,
                          maxScale: 48,
                          child: SizedBox.fromSize(
                            size: size,
                            child: TextOnPath(
                              _sample.text,
                              curve: _curve(size),
                              style: _sample.style(fontSize),
                              mode: _mode,
                              rendering: rendering,
                              showMesh: _mesh,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Row(
                        children: [
                          OutlinedButton(onPressed: () => _export(size, 'svg'), child: const Text('Save SVG')),
                          const SizedBox(width: 8),
                          OutlinedButton(onPressed: () => _export(size, 'pdf'), child: const Text('Save PDF')),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
