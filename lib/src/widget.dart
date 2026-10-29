import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'curve.dart';
import 'outline.dart';
import 'placement.dart';
import 'shaped_text.dart';

/// How [TextOnPath] draws its text.
enum TextOnPathRendering {
  /// From an atlas drawn again for the scale it's shown at (the zoom of any [Transform] or [InteractiveViewer] above
  /// it, times the screen's pixel ratio), so it stays sharp; from traced outlines once an atlas would grow past
  /// [TextOnPath.maxAtlasTexels].
  auto,

  /// From one atlas, drawn for the screen at rest: softens when zoomed in.
  raster,

  /// From traced outlines ([TextOutlines]): sharp at any zoom. Matches the font's edges to a few hundredths of a pixel
  /// at the text's own size, and tracing takes a moment the first time.
  vector,
}

/// Text laid along [curve], with cursive joins kept closed.
///
/// The curve is in this widget's own coordinates; the widget fills the space it's given. The text is shaped once and
/// drawn as a mesh, so moving or reshaping the curve is cheap; changing the text or its style shapes it again.
class TextOnPath extends StatefulWidget {
  const TextOnPath(
    this.text, {
    super.key,
    required this.curve,
    this.style,
    this.textDirection,
    this.mode = TextOnPathMode.joined,
    this.fit = TextOnPathFit.none,
    this.fitLength,
    this.position = 0.5,
    this.rendering = TextOnPathRendering.auto,
    this.oversample = 2,
    this.maxAtlasTexels = 16 << 20,
    this.connection = const ConnectionLine.auto(),
    this.showMesh = false,
  });

  /// The text.
  final String text;

  /// The curve its baseline runs along.
  final PathCurve curve;

  /// Its style, merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Its direction; guessed from its first letters when null.
  final TextDirection? textDirection;

  /// How each cluster is put on the curve.
  final TextOnPathMode mode;

  /// How the text fills [fitLength] (by default, the curve's length).
  final TextOnPathFit fit;

  /// The length to fit the text to.
  final double? fitLength;

  /// Where the middle of the text goes, as a fraction of the curve's length.
  final double position;

  /// How the text is drawn.
  final TextOnPathRendering rendering;

  /// Atlas texels to each pixel on the screen. Two matches native text most closely.
  final double oversample;

  /// The most texels an atlas may hold before [TextOnPathRendering.auto] turns to outlines.
  final int maxAtlasTexels;

  /// Which rows the letters join on.
  final ConnectionLine connection;

  /// Draws the mesh's grid over the text.
  final bool showMesh;

  /// The atlas density, in texels per logical pixel, that [TextOnPathRendering.auto] draws for text shown at [scale]
  /// screen pixels to each of its logical pixels: [oversample] texels a screen pixel, rounded up to a power of the
  /// square root of two, so that zooming draws a new atlas only now and then.
  static double atlasDensityFor(double scale, {double oversample = 2}) =>
      math.pow(2, (2 * math.log(scale * oversample) / math.ln2 - 1e-9).ceil() / 2).toDouble();

  @override
  State<TextOnPath> createState() => _TextOnPathState();
}

class _TextOnPathState extends State<TextOnPath> {
  ShapedText? _shaped;
  Object? _shapedFor;
  int _generation = 0;

  // The atlas drawn for the current scale, when it isn't the shaped text's own, and the scale asked for next.
  TextAtlas? _atlas;
  double? _drawing;
  TextOutlines? _outlines;
  bool _tracing = false;
  bool _useOutlines = false;
  double? _shownScale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shape();
  }

  @override
  void didUpdateWidget(TextOnPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    _shape();
    if (widget.rendering != oldWidget.rendering) {
      _useOutlines = widget.rendering == TextOnPathRendering.vector;
      if (_useOutlines) _trace();
      // The scale it's shown at hasn't changed, so it won't be reported again: act on the last one.
      final scale = _shownScale;
      if (scale != null) SchedulerBinding.instance.addPostFrameCallback((_) => _shownAt(scale));
    }
  }

  void _shape() {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final key = (widget.text, style, widget.textDirection, widget.connection);
    if (key == _shapedFor) return;
    _shapedFor = key;
    final generation = ++_generation;
    ShapedText.layout(
      widget.text,
      style,
      textDirection: widget.textDirection,
      scale: ratio * widget.oversample,
      connection: widget.connection,
    ).then((shaped) {
      if (!mounted || generation != _generation) {
        shaped.dispose();
        return;
      }
      setState(() {
        _shaped?.dispose();
        _atlas?.dispose();
        _shaped = shaped;
        _atlas = null;
        _drawing = null;
        _outlines = null;
        _tracing = false;
        _useOutlines = widget.rendering == TextOnPathRendering.vector;
      });
      if (_useOutlines) _trace();
    });
  }

  /// Called after a frame with the scale the text was shown at, in screen pixels to each of its logical pixels.
  void _shownAt(double scale) {
    _shownScale = scale;
    final shaped = _shaped;
    if (!mounted || shaped == null || widget.rendering != TextOnPathRendering.auto) return;
    final want = TextOnPath.atlasDensityFor(scale, oversample: widget.oversample);
    final current = _atlas?.density ?? shaped.atlas.density;
    if (shaped.texelsAt(want) > widget.maxAtlasTexels) {
      if (!_useOutlines) setState(() => _useOutlines = true);
      _trace();
      return;
    }
    if (_useOutlines) setState(() => _useOutlines = false);
    if ((current / want - 1).abs() < 0.01 || _drawing == want) return;
    if ((shaped.atlas.density / want - 1).abs() < 0.01) {
      setState(() {
        _atlas?.dispose();
        _atlas = null;
      });
      return;
    }
    _drawing = want;
    final generation = _generation;
    shaped.drawAtlas(want).then((atlas) {
      if (!mounted || generation != _generation || _drawing != want) {
        atlas.dispose();
        return;
      }
      setState(() {
        final old = _atlas;
        _atlas = atlas;
        _drawing = null;
        // The frame being built still paints the old one.
        SchedulerBinding.instance.addPostFrameCallback((_) => old?.dispose());
      });
    });
  }

  void _trace() {
    final shaped = _shaped;
    if (shaped == null || _outlines != null || _tracing) return;
    _tracing = true;
    final generation = _generation;
    TextOutlines.trace(shaped).then((outlines) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _outlines = outlines;
        _tracing = false;
      });
    });
  }

  @override
  void dispose() {
    _shaped?.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shaped = _shaped;
    if (shaped == null) return const SizedBox.expand();
    return _TextOnPathPaint(
      placement: TextOnPathPlacement(
        shaped,
        widget.curve,
        mode: widget.mode,
        fit: widget.fit,
        fitLength: widget.fitLength,
        position: widget.position,
      ),
      atlas: widget.rendering == TextOnPathRendering.auto ? _atlas : null,
      outlines: _useOutlines ? _outlines : null,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      showMesh: widget.showMesh,
      onShownAt: _shownAt,
    );
  }
}

class _TextOnPathPaint extends LeafRenderObjectWidget {
  const _TextOnPathPaint({
    required this.placement,
    required this.atlas,
    required this.outlines,
    required this.devicePixelRatio,
    required this.showMesh,
    required this.onShownAt,
  });

  final TextOnPathPlacement placement;
  final TextAtlas? atlas;
  final TextOutlines? outlines;
  final double devicePixelRatio;
  final bool showMesh;
  final ValueChanged<double> onShownAt;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTextOnPath(
        placement,
        atlas,
        outlines,
        devicePixelRatio,
        showMesh,
        onShownAt,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderTextOnPath renderObject) {
    renderObject
      ..placement = placement
      ..atlas = atlas
      ..outlines = outlines
      ..devicePixelRatio = devicePixelRatio
      ..showMesh = showMesh
      ..onShownAt = onShownAt;
  }
}

class _RenderTextOnPath extends RenderBox {
  _RenderTextOnPath(
    this._placement,
    this._atlas,
    this._outlines,
    this._devicePixelRatio,
    this._showMesh,
    this.onShownAt,
  );

  TextOnPathPlacement _placement;
  set placement(TextOnPathPlacement value) {
    _placement = value;
    markNeedsPaint();
  }

  TextAtlas? _atlas;
  set atlas(TextAtlas? value) {
    if (value == _atlas) return;
    _atlas = value;
    markNeedsPaint();
  }

  TextOutlines? _outlines;
  set outlines(TextOutlines? value) {
    if (value == _outlines) return;
    _outlines = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  bool _showMesh;
  set showMesh(bool value) {
    if (value == _showMesh) return;
    _showMesh = value;
    markNeedsPaint();
  }

  ValueChanged<double> onShownAt;
  double? _reported;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    // How many screen pixels each of this box's pixels covers: every transform above it, and the screen's density.
    final m = getTransformTo(null).storage;
    final scale =
        _devicePixelRatio * math.max(math.sqrt(m[0] * m[0] + m[1] * m[1]), math.sqrt(m[4] * m[4] + m[5] * m[5]));
    if (scale != _reported) {
      _reported = scale;
      SchedulerBinding.instance.addPostFrameCallback((_) => onShownAt(scale));
    }
    final canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    final outlines = _outlines;
    if (outlines != null) {
      _placement.paintOutlines(canvas, outlines);
    } else {
      _placement.paint(canvas, atlas: _atlas);
    }
    if (_showMesh) {
      canvas.drawPath(
        _placement.meshPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0x660077CC),
      );
    }
    canvas.restore();
  }
}
