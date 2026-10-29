import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
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
    shaped.drawAtlas(want).then(
      (atlas) {
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
      },
      // An atlas that wouldn't fit one texture: its outlines instead.
      onError: (Object _) {
        if (!mounted || generation != _generation || _drawing != want) return;
        _drawing = null;
        setState(() => _useOutlines = true);
        _trace();
      },
    );
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
      registrar: SelectionContainer.maybeOf(context),
      selectionColor: DefaultSelectionStyle.of(context).selectionColor,
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
    required this.registrar,
    required this.selectionColor,
  });

  final TextOnPathPlacement placement;
  final TextAtlas? atlas;
  final TextOutlines? outlines;
  final double devicePixelRatio;
  final bool showMesh;
  final ValueChanged<double> onShownAt;
  final SelectionRegistrar? registrar;
  final Color? selectionColor;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTextOnPath(
        placement,
        atlas,
        outlines,
        devicePixelRatio,
        showMesh,
        onShownAt,
        selectionColor,
      )..registrar = registrar;

  @override
  void updateRenderObject(BuildContext context, _RenderTextOnPath renderObject) {
    renderObject
      ..placement = placement
      ..atlas = atlas
      ..outlines = outlines
      ..devicePixelRatio = devicePixelRatio
      ..showMesh = showMesh
      ..onShownAt = onShownAt
      ..registrar = registrar
      ..selectionColor = selectionColor;
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
    this._selectionColor,
  );

  TextOnPathPlacement _placement;
  set placement(TextOnPathPlacement value) {
    final sameText = value.text == _placement.text;
    _placement = value;
    markNeedsPaint();
    if (sameText) {
      _selectable?.placementChanged();
    } else {
      _updateSelectable();
    }
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

  Color? _selectionColor;
  set selectionColor(Color? value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    if (_selectable?.hasSelection ?? false) markNeedsPaint();
  }

  ValueChanged<double> onShownAt;
  double? _reported;

  // Selection: one selectable for the shaped text, registered while there's a registrar to take it.
  SelectionRegistrar? _registrar;
  set registrar(SelectionRegistrar? value) {
    if (value == _registrar) return;
    _registrar = value;
    _updateSelectable();
  }

  _CurvedSelectable? _selectable;

  void _updateSelectable() {
    if (_registrar == null || !attached) {
      _removeSelectable();
      return;
    }
    if (_selectable?.text == _placement.text) return;
    _removeSelectable();
    _selectable = _CurvedSelectable(this, _placement.text)..registrar = _registrar;
    markNeedsCompositingBitsUpdate();
  }

  void _removeSelectable() {
    final selectable = _selectable;
    if (selectable == null) return;
    _selectable = null;
    selectable
      ..registrar = null
      ..dispose();
    markNeedsCompositingBitsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateSelectable();
  }

  @override
  void detach() {
    _removeSelectable();
    super.detach();
  }

  @override
  void dispose() {
    _removeSelectable();
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => _selectable?.hasHandles ?? false;

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
    final selectable = _selectable, colour = _selectionColor;
    if (selectable != null && colour != null) {
      final paint = Paint()..color = colour;
      for (final band in selectable.highlight()) {
        canvas.drawPath(Path()..addPolygon(band, true), paint);
      }
    }
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
    selectable?.paintHandles(context, offset);
  }
}

/// The curved text as one [Selectable]: a pointer is carried back to the straight line, where the paragraph finds
/// the position, the word, the direction; the highlight is drawn along the curve, and the handles turned to it.
class _CurvedSelectable with ChangeNotifier, Selectable, SelectionRegistrant {
  _CurvedSelectable(this._box, this.text);

  final _RenderTextOnPath _box;

  /// The text it selects in.
  final ShapedText text;

  TextPosition? _start, _end;
  LayerLink? _startHandle, _endHandle;
  // The curve's direction at each handle, to turn it by.
  Offset _startTangent = const Offset(1, 0), _endTangent = const Offset(1, 0);
  SelectionGeometry _geometry = const SelectionGeometry(status: SelectionStatus.none, hasContent: true);

  TextOnPathPlacement get _placement => _box._placement;
  ui.Paragraph get _paragraph => text.paragraph;
  int get _length => text.text.length;

  bool get hasSelection => _start != null && _end != null && _start!.offset != _end!.offset;
  bool get hasHandles => _startHandle != null || _endHandle != null;

  @override
  SelectionGeometry get value => _geometry;

  /// The curve moved: the selection keeps its place in the text and is drawn where the text now is.
  void placementChanged() {
    // Not while a frame is being built: listeners may rebuild.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_box._selectable == this) _updateGeometry();
    });
  }

  void _updateGeometry() {
    final next = _computeGeometry();
    if (next == _geometry) return;
    _geometry = next;
    notifyListeners();
  }

  SelectionGeometry _computeGeometry() {
    final start = _start, end = _end;
    if (start == null || end == null) {
      return const SelectionGeometry(status: SelectionStatus.none, hasContent: true);
    }
    final collapsed = start.offset == end.offset;
    final flip = (start.offset > end.offset) != (text.textDirection == TextDirection.rtl);
    final (startType, endType) = collapsed
        ? (TextSelectionHandleType.collapsed, TextSelectionHandleType.collapsed)
        : (flip
            ? (TextSelectionHandleType.right, TextSelectionHandleType.left)
            : (TextSelectionHandleType.left, TextSelectionHandleType.right));
    final (startPoint, startTangent) = _edge(start);
    final (endPoint, endTangent) = collapsed ? (startPoint, startTangent) : _edge(end);
    _startTangent = startTangent;
    _endTangent = endTangent;
    final lineHeight = _paragraph.height;
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(localPosition: startPoint, lineHeight: lineHeight, handleType: startType),
      endSelectionPoint: SelectionPoint(localPosition: endPoint, lineHeight: lineHeight, handleType: endType),
      selectionRects: [for (final band in highlight()) _boundsOf(band)],
      status: collapsed ? SelectionStatus.collapsed : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  static Rect _boundsOf(List<Offset> points) {
    var box = Rect.fromPoints(points.first, points.first);
    for (final p in points.skip(1)) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    return box;
  }

  /// Where the caret for [position] stands on the curve, at the foot of the line, and the curve's direction there.
  (Offset, Offset) _edge(TextPosition position) => _placement.bandPoint(_caretX(position), _paragraph.height);

  /// The caret's column for [position] in the straight line: before the cluster that starts there, or after the one
  /// that ends there, whichever way it runs.
  double _caretX(TextPosition position) {
    if (position.offset < _length) {
      final glyph = _paragraph.getGlyphInfoAt(position.offset);
      if (glyph != null) {
        final b = glyph.graphemeClusterLayoutBounds;
        return glyph.writingDirection == TextDirection.rtl ? b.right : b.left;
      }
    }
    if (position.offset > 0) {
      final glyph = _paragraph.getGlyphInfoAt(position.offset - 1);
      if (glyph != null) {
        final b = glyph.graphemeClusterLayoutBounds;
        return glyph.writingDirection == TextDirection.rtl ? b.left : b.right;
      }
    }
    return 0;
  }

  /// The selection's highlight: for each box the straight line gives the selected range (more than one where
  /// directions mix), a band along the curve.
  List<List<Offset>> highlight() {
    final start = _start, end = _end;
    if (start == null || end == null || start.offset == end.offset) return const [];
    final boxes = _paragraph.getBoxesForRange(math.min(start.offset, end.offset), math.max(start.offset, end.offset));
    return [for (final b in boxes) _placement.band(b.left, b.right, b.top, b.bottom)];
  }

  /// The text position nearest the local [point].
  TextPosition _positionAt(Offset point) {
    final flat = _placement.toFlat(point);
    return _paragraph.getPositionForOffset(Offset(flat.dx, flat.dy.clamp(0.0, _paragraph.height)));
  }

  Rect get _area => _placement.bounds.inflate(0.25 * text.fontSize);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final start = _start, end = _end;
    final SelectionResult result;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final edge = event as SelectionEdgeUpdateEvent;
        result = _moveEdge(
          edge.globalPosition,
          isEnd: event.type == SelectionEventType.endEdgeUpdate,
          byWord: edge.granularity == TextGranularity.word,
        );
      case SelectionEventType.clear:
        _start = _end = null;
        result = SelectionResult.none;
      case SelectionEventType.selectAll:
        _selectAll();
        result = SelectionResult.none;
      case SelectionEventType.selectWord:
        result = _selectWord((event as SelectWordSelectionEvent).globalPosition);
      case SelectionEventType.selectParagraph:
        final paragraph = event as SelectParagraphSelectionEvent;
        _selectAll();
        result = paragraph.absorb ? SelectionResult.next : SelectionResult.end;
      case SelectionEventType.granularlyExtendSelection:
        result = _extend(event as GranularlyExtendSelectionEvent);
      case SelectionEventType.directionallyExtendSelection:
        final extend = event as DirectionallyExtendSelectionEvent;
        final forward = switch (extend.direction) {
          SelectionExtendDirection.nextLine || SelectionExtendDirection.forward => true,
          SelectionExtendDirection.previousLine || SelectionExtendDirection.backward => false,
        };
        _ensureSelection(forward);
        _setEdge(TextPosition(offset: forward ? _length : 0), isEnd: extend.isEnd);
        result = forward ? SelectionResult.next : SelectionResult.previous;
    }
    if (start != _start || end != _end) {
      _box.markNeedsPaint();
      _updateGeometry();
    }
    return result;
  }

  void _setEdge(TextPosition position, {required bool isEnd}) {
    if (isEnd) {
      _end = position;
    } else {
      _start = position;
    }
  }

  void _selectAll() {
    _start = const TextPosition(offset: 0);
    _end = TextPosition(offset: _length, affinity: TextAffinity.upstream);
  }

  void _ensureSelection(bool forward) {
    if (_start != null && _end != null) return;
    _start = _end = TextPosition(offset: forward ? 0 : _length);
  }

  SelectionResult _moveEdge(Offset global, {required bool isEnd, required bool byWord}) {
    final local = _box.globalToLocal(global);
    var position = _positionAt(local);
    if (byWord) {
      final word = _paragraph.getWordBoundary(position);
      final other = isEnd ? _start : _end;
      // Take in the whole word on the side away from the edge that stays put.
      position = other == null || position.offset >= other.offset
          ? TextPosition(offset: word.end, affinity: TextAffinity.upstream)
          : TextPosition(offset: word.start);
    }
    _setEdge(position, isEnd: isEnd);
    if (position.offset >= _length) return SelectionResult.next;
    if (position.offset <= 0) return SelectionResult.previous;
    return SelectionUtils.getResultBasedOnRect(_area, local);
  }

  SelectionResult _selectWord(Offset global) {
    final local = _box.globalToLocal(global);
    if (!_area.contains(local)) return SelectionUtils.getResultBasedOnRect(_area, local);
    final word = _paragraph.getWordBoundary(_positionAt(local));
    _start = TextPosition(offset: word.start);
    _end = TextPosition(offset: word.end, affinity: TextAffinity.upstream);
    return SelectionResult.end;
  }

  SelectionResult _extend(GranularlyExtendSelectionEvent event) {
    _ensureSelection(event.forward);
    final from = (event.isEnd ? _end : _start)!.offset;
    final to = switch (event.granularity) {
      TextGranularity.character => event.forward ? _nextCluster(from) : _previousCluster(from),
      TextGranularity.word => event.forward ? _nextWordEnd(from) : _previousWordStart(from),
      TextGranularity.line || TextGranularity.paragraph || TextGranularity.document => event.forward ? _length : 0,
    };
    _setEdge(TextPosition(offset: to), isEnd: event.isEnd);
    if (event.forward && to >= _length) return SelectionResult.next;
    if (!event.forward && to <= 0) return SelectionResult.previous;
    return SelectionResult.end;
  }

  int _nextCluster(int offset) {
    if (offset >= _length) return _length;
    return _paragraph.getGlyphInfoAt(offset)?.graphemeClusterCodeUnitRange.end ?? offset + 1;
  }

  int _previousCluster(int offset) {
    if (offset <= 0) return 0;
    return _paragraph.getGlyphInfoAt(offset - 1)?.graphemeClusterCodeUnitRange.start ?? offset - 1;
  }

  int _nextWordEnd(int offset) {
    var at = offset;
    while (at < _length) {
      final word = _paragraph.getWordBoundary(TextPosition(offset: at));
      if (word.end > offset && text.text.substring(at, word.end).trim().isNotEmpty) return word.end;
      at = math.max(word.end, at + 1);
    }
    return _length;
  }

  int _previousWordStart(int offset) {
    var at = offset;
    while (at > 0) {
      final word = _paragraph.getWordBoundary(TextPosition(offset: at - 1));
      if (word.start < offset && text.text.substring(word.start, at).trim().isNotEmpty) return word.start;
      at = math.min(word.start, at - 1);
    }
    return 0;
  }

  @override
  SelectedContent? getSelectedContent() {
    final start = _start, end = _end;
    if (start == null || end == null) return null;
    return SelectedContent(
      plainText: text.text.substring(math.min(start.offset, end.offset), math.max(start.offset, end.offset)),
    );
  }

  @override
  SelectedContentRange? getSelection() {
    final start = _start, end = _end;
    if (start == null || end == null) return null;
    return SelectedContentRange(startOffset: start.offset, endOffset: end.offset);
  }

  @override
  int get contentLength => _length;

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) => _box.getTransformTo(ancestor);

  @override
  Size get size => _box.size;

  @override
  List<Rect> get boundingBoxes => [
        for (final r in _placement.clusterBounds)
          if (!r.isEmpty) r
      ];

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (!_box.attached) {
      // Only clearing up after the box has gone.
      _startHandle = startHandle;
      _endHandle = endHandle;
      return;
    }
    if (startHandle == _startHandle && endHandle == _endHandle) return;
    final had = hasHandles;
    _startHandle = startHandle;
    _endHandle = endHandle;
    if (had != hasHandles) _box.markNeedsCompositingBitsUpdate();
    _box.markNeedsPaint();
  }

  /// Puts the handles' leaders at the selection's ends, turned to the curve, so the handles follow it.
  void paintHandles(PaintingContext context, Offset offset) {
    for (final (link, point, tangent) in [
      (_startHandle, _geometry.startSelectionPoint, _startTangent),
      (_endHandle, _geometry.endSelectionPoint, _endTangent),
    ]) {
      if (link == null || point == null) continue;
      final at = point.localPosition;
      // Turned about the handle's point: in columns, a rotation and the shift that keeps the point in place.
      final angle = math.atan2(tangent.dy, tangent.dx), c = math.cos(angle), sn = math.sin(angle);
      final turn = Matrix4(
          c, sn, 0, 0, -sn, c, 0, 0, 0, 0, 1, 0, at.dx - c * at.dx + sn * at.dy, at.dy - sn * at.dx - c * at.dy, 0, 1);
      context.pushTransform(true, offset, turn, (context, offset) {
        context.pushLayer(LeaderLayer(link: link, offset: offset + at), (context, offset) {}, Offset.zero);
      });
    }
  }
}
