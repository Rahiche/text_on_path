import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Text shaped once, as one straight line, by Flutter's own paragraph engine, then drawn one grapheme cluster at a
/// time into an atlas.
///
/// Shaping the whole run at once keeps every script right: Arabic letters take their joining forms, Devanagari and
/// Bengali their conjuncts and vowel signs. Each cluster is then drawn alone, with the rest of the run transparent, so
/// it keeps the exact shape and place it had in the run (an overhanging tail and all) and can be moved on its own.
///
/// The flat run's coordinates are the paragraph's: x to the right, y down from the top of the line.
class ShapedText {
  ShapedText._({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.width,
    required this.height,
    required this.baseline,
    required this.units,
    required this.neighbours,
    required this.atlas,
    required this.band,
    required Uint8List alpha,
    required int atlasWidth,
  })  : _alpha = alpha,
        _atlasWidth = atlasWidth;

  /// Shapes [text] in [style] and draws its clusters into an atlas at [scale] texels per logical pixel.
  ///
  /// [connection] says which rows the script's letters join on; by default they're found from the run itself.
  static Future<ShapedText> layout(
    String text,
    TextStyle style, {
    TextDirection? textDirection,
    double scale = 2,
    ConnectionLine connection = const ConnectionLine.auto(),
  }) async {
    final direction = textDirection ?? _guessDirection(text);
    final full = _paragraph(text, style, direction);
    final width = full.width;
    final height = full.height;
    final baseline = full.alphabeticBaseline;
    final fontSize = style.fontSize ?? 14;

    // Grapheme clusters in visual order, left to right. Spaces have no ink and only push their neighbours apart.
    var ranges = <TextRange>[];
    for (var i = 0; i < text.length;) {
      final glyph = full.getGlyphInfoAt(i);
      if (glyph == null) {
        i++;
        continue;
      }
      final r = glyph.graphemeClusterCodeUnitRange;
      if (text.substring(r.start, r.end).trim().isNotEmpty) ranges.add(r);
      i = math.max(r.end, i + 1);
    }

    // A ligature lives in the first of its clusters, so the others draw nothing alone; those are merged in and the
    // atlas drawn again.
    // What ties an atlas to the text it was drawn from.
    final identity = Object();
    for (var attempt = 0;; attempt++) {
      final boxes = [for (final r in ranges) _box(full, r)];
      final atlas = await _Atlas.draw(text, style, direction, ranges, boxes, width, height, fontSize, scale);
      final empty = <int>[];
      for (var u = 0; u < atlas.units.length; u++) {
        if (atlas.units[u].ink.isEmpty) empty.add(u);
      }
      if (empty.isEmpty || attempt == 2) {
        final units = atlas.units..sort((a, b) => a.box.left.compareTo(b.box.left));
        final shaped = ShapedText._(
          text: text,
          style: style,
          textDirection: direction,
          width: width,
          height: height,
          baseline: baseline,
          units: units,
          neighbours: const [],
          atlas: TextAtlas._(
            atlas.image,
            scale,
            [for (final u in units) u.cell],
            [for (final u in units) u.cellOrigin],
            identity,
          ),
          band: null,
          alpha: atlas.alpha,
          atlasWidth: atlas.image.width,
        );
        return shaped._analyse(connection);
      }
      atlas.image.dispose();
      ranges = _mergeEmpty(ranges, empty);
    }
  }

  /// The text, as given.
  final String text;

  /// The style it was shaped in.
  final TextStyle style;

  /// The run's direction.
  final TextDirection textDirection;

  /// The flat run's width, height and baseline.
  final double width, height, baseline;

  /// The run's clusters with ink, left to right as they're seen.
  final List<TextUnit> units;

  /// Each pair of clusters side by side in the run, left to right, and whether they join.
  final List<UnitPair> neighbours;

  /// Every cluster drawn alone, each in its own cell, at [scale] texels per logical pixel. It's also what the run's
  /// joins are found from; [drawAtlas] draws others, at the density a zoomed view needs.
  final TextAtlas atlas;

  /// The atlas's texels per logical pixel.
  double get scale => atlas.density;

  /// The rows the script's letters join on: the Arabic baseline, the Indic headline. Null when nothing joins.
  final ConnectionBand? band;

  final Uint8List _alpha;
  final int _atlasWidth;

  /// The font size.
  double get fontSize => style.fontSize ?? 14;

  /// How much of [unit]'s ink covers the flat point ([x], [y]), from 0 to 1.
  double coverage(TextUnit unit, double x, double y) {
    final tx = (unit.cell.left + (x - unit.cellOrigin.dx) * scale).floor();
    final ty = (unit.cell.top + (y - unit.cellOrigin.dy) * scale).floor();
    if (tx < unit.cell.left || ty < unit.cell.top || tx >= unit.cell.right || ty >= unit.cell.bottom) return 0;
    return _alpha[ty * _atlasWidth + tx] / 255;
  }

  /// The flat rectangle round [unit]'s ink that's drawn: its ink and a pixel more, for the edges' antialiasing.
  Rect drawnRect(TextUnit unit) => unit.ink.inflate(1);

  /// How many texels an atlas drawn at [density] holds.
  int texelsAt(double density) {
    var total = 0;
    for (final u in units) {
      if (u.ink.isEmpty) continue;
      final r = drawnRect(u);
      total += ((r.width * density).ceil() + 4) * ((r.height * density).ceil() + 4);
    }
    return total;
  }

  /// Draws every cluster again, alone in a cell cropped to its ink, at [density] texels per logical pixel.
  ///
  /// The cells hold only what the mesh draws, so an atlas for a zoomed view costs a fraction of [atlas]. Throws if
  /// it wouldn't fit one texture; check [texelsAt] first.
  Future<TextAtlas> drawAtlas(double density) async {
    final pad = 2 / density;
    final rects = [for (final u in units) u.ink.isEmpty ? Rect.zero : drawnRect(u).inflate(pad)];
    final sizes = [
      for (final r in rects) Size((r.width * density).ceilToDouble(), (r.height * density).ceilToDouble())
    ];
    final widest = sizes.fold(0.0, (m, s) => math.max(m, s.width));
    final rowWidth = math.max(widest, math.min(4096.0, math.sqrt(texelsAt(density)) * 1.3));
    final cells = <Rect>[];
    var x = 0.0, y = 0.0, row = 0.0, atlasWidth = 1.0;
    for (final size in sizes) {
      if (x > 0 && x + size.width > rowWidth) {
        x = 0;
        y += row + 1;
        row = 0;
      }
      cells.add(Rect.fromLTWH(x, y, size.width, size.height));
      x += size.width + 1;
      row = math.max(row, size.height);
      atlasWidth = math.max(atlasWidth, x);
    }
    final atlasHeight = math.max(1.0, y + row);
    if (atlasWidth > maxTextureSide || atlasHeight > maxTextureSide) {
      throw StateError('An atlas at $density texels per pixel would be ${atlasWidth.ceil()}×${atlasHeight.ceil()}.');
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < units.length; i++) {
      if (units[i].ink.isEmpty) continue;
      canvas
        ..save()
        ..translate(cells[i].left, cells[i].top)
        ..clipRect(Offset.zero & cells[i].size)
        ..scale(density)
        ..translate(-rects[i].left, -rects[i].top)
        ..drawParagraph(isolatedParagraph(this, units[i].range), Offset.zero)
        ..restore();
    }
    final image = await recorder.endRecording().toImage(atlasWidth.ceil(), atlasHeight.ceil());
    return TextAtlas._(image, density, cells, [for (final r in rects) r.topLeft], atlas._owner);
  }

  /// The longest side an atlas may have: what GPUs reliably take.
  static const maxTextureSide = 8192;

  /// Points across [unit]'s ink, about [spacing] logical pixels apart, with their coverage: `(x, y, coverage)`.
  Iterable<(double, double, double)> inkSamples(TextUnit unit, {double spacing = 0.5}) sync* {
    final step = math.max(1, (spacing * scale).round());
    final ink = unit.ink;
    final x0 = (unit.cell.left + (ink.left - unit.cellOrigin.dx) * scale).floor();
    final x1 = (unit.cell.left + (ink.right - unit.cellOrigin.dx) * scale).ceil();
    final y0 = (unit.cell.top + (ink.top - unit.cellOrigin.dy) * scale).floor();
    final y1 = (unit.cell.top + (ink.bottom - unit.cellOrigin.dy) * scale).ceil();
    for (var ty = y0; ty < y1; ty += step) {
      for (var tx = x0; tx < x1; tx += step) {
        final a = _alpha[ty * _atlasWidth + tx];
        if (a == 0) continue;
        yield (
          unit.cellOrigin.dx + (tx + 0.5 - unit.cell.left) / scale,
          unit.cellOrigin.dy + (ty + 0.5 - unit.cell.top) / scale,
          a / 255,
        );
      }
    }
  }

  /// Frees the atlas.
  void dispose() => atlas.dispose();

  /// [text] laid out again with only [range] visible: the rest of the run transparent, so the visible part keeps the
  /// shape and place the whole run gives it.
  ui.Paragraph isolated(TextRange range) => _paragraph(text, style, textDirection, only: range);

  /// Finds which neighbours join, the rows they join on, and how much of each join is bare stroke.
  ShapedText _analyse(ConnectionLine connection) {
    final pairs = <UnitPair>[];
    final crossings = <List<(double, double)>>[];
    for (var i = 0; i + 1 < units.length; i++) {
      final a = units[i], b = units[i + 1];
      final touching = (b.box.left - a.box.right).abs() < 0.75;
      final x = (a.box.right + b.box.left) / 2;
      crossings.add(touching ? _crossing(a, b, x) : const []);
      pairs.add(UnitPair._(i, i + 1, x, touching));
    }

    // The joining rows: where the most joins cross between their two letters.
    final rows = ((height + 2 * _Atlas.marginY(fontSize)) * scale).ceil();
    final top = -_Atlas.marginY(fontSize);
    final count = List<int>.filled(rows, 0);
    var joined = 0;
    for (final c in crossings) {
      if (c.isEmpty) continue;
      joined++;
      for (final (y0, y1) in c) {
        for (var r = ((y0 - top) * scale).floor(); r < ((y1 - top) * scale).ceil(); r++) {
          if (r >= 0 && r < rows) count[r]++;
        }
      }
    }
    ConnectionBand? band;
    final fixed = connection._resolve(baseline, fontSize);
    if (fixed != null) {
      band = fixed;
    } else if (joined > 0) {
      var peak = 0;
      for (var r = 1; r < rows; r++) {
        if (count[r] > count[peak]) peak = r;
      }
      final floor = math.max(1, (count[peak] * 0.5).ceil());
      var r0 = peak, r1 = peak;
      while (r0 > 0 && count[r0 - 1] >= floor) {
        r0--;
      }
      while (r1 + 1 < rows && count[r1 + 1] >= floor) {
        r1++;
      }
      band = ConnectionBand(top + r0 / scale, top + (r1 + 1) / scale);
    }

    // A pair joins when ink runs across the boundary between them, in the joining rows.
    final result = <UnitPair>[];
    for (var i = 0; i < pairs.length; i++) {
      final p = pairs[i];
      final c = crossings[i];
      var inBand = false;
      if (band != null) {
        for (final (y0, y1) in c) {
          if (y1 > band.top - 0.5 && y0 < band.bottom + 0.5) inBand = true;
        }
      }
      final stretchable = inBand && band != null;
      result.add(
        UnitPair._(
          p.left,
          p.right,
          p.x,
          p.touching,
          joins: c.isNotEmpty,
          inBand: inBand,
          crossing: c,
          slope: c.isEmpty ? 0 : _slope(units[p.left], units[p.right], p.x, c.first),
          leftBare: stretchable ? _bare(units[p.left], p.x, -1, band) : 0,
          rightBare: stretchable ? _bare(units[p.right], p.x, 1, band) : 0,
        ),
      );
    }
    return ShapedText._(
      text: text,
      style: style,
      textDirection: textDirection,
      width: width,
      height: height,
      baseline: baseline,
      units: units,
      neighbours: result,
      atlas: atlas,
      band: band,
      alpha: _alpha,
      atlasWidth: _atlasWidth,
    );
  }

  /// The rows where [a]'s ink reaches the boundary [x] from the left and [b]'s from the right: the stroke joining them.
  List<(double, double)> _crossing(TextUnit a, TextUnit b, double x) {
    final y0 = math.max(a.ink.top, b.ink.top), y1 = math.min(a.ink.bottom, b.ink.bottom);
    if (a.ink.isEmpty || b.ink.isEmpty || y1 <= y0) return const [];
    final step = 1 / scale;
    final out = <(double, double)>[];
    double? start;
    for (var y = y0 + step / 2; y < y1; y += step) {
      var ca = 0.0, cb = 0.0;
      for (var d = 0.0; d <= 1.0; d += step) {
        ca = math.max(ca, coverage(a, x - d - step / 2, y));
        cb = math.max(cb, coverage(b, x + d + step / 2, y));
      }
      final crosses = ca >= 0.5 && cb >= 0.5;
      if (crosses && start == null) start = y - step / 2;
      if (!crosses && start != null) {
        out.add((start, y - step / 2));
        start = null;
      }
    }
    if (start != null) out.add((start, y1));
    // A speck isn't a join.
    return out.where((r) => r.$2 - r.$1 >= 1.5 * step).toList();
  }

  /// How steeply the stroke joining [a] and [b] runs across the boundary [x], where it crosses at [rows]: how far its
  /// edges move (down, in the flat run) from a little way into [a] to as far into [b], over the run between.
  ///
  /// In each of those columns it takes the run of ink that holds the crossing, and whichever of its edges moved less:
  /// a stem hanging from a headline, or rising from a baseline stroke, moves only one.
  double _slope(TextUnit a, TextUnit b, double x, (double, double) rows) {
    final (y0, y1) = rows;
    double? shift(TextUnit unit, double cx) {
      final step = 1 / scale;
      final reach = 0.4 * fontSize;
      double? best;
      var bestDistance = double.infinity;
      double? start;
      for (var y = y0 - reach; y <= y1 + reach + step; y += step) {
        final inside = y <= y1 + reach && coverage(unit, cx, y) >= 0.5;
        if (inside && start == null) start = y;
        if (!inside && start != null) {
          final top = start - y0, bottom = y - y1;
          final moved = top.abs() < bottom.abs() ? top : bottom;
          if (moved.abs() < bestDistance) {
            bestDistance = moved.abs();
            best = moved;
          }
          start = null;
        }
      }
      return best;
    }

    // Measured a twentieth and a tenth of an em out; the flatter wins, since a mark or a stem nearby can only add a
    // slope that isn't the stroke's.
    double? at(double d) {
      final sa = shift(a, x - d), sb = shift(b, x + d);
      return sa == null || sb == null ? null : (sb - sa) / (2 * d);
    }

    final near = at(0.05 * fontSize), far = at(0.1 * fontSize);
    if (near == null || far == null) return near ?? far ?? 0;
    return near.abs() < far.abs() ? near : far;
  }

  /// How far into [unit] from the boundary [x] (going [direction]: -1 left, 1 right) its ink stays inside [band]: the
  /// bare stroke that can be stretched without touching a letter.
  double _bare(TextUnit unit, double x, int direction, ConnectionBand band) {
    final step = 1 / scale;
    final slack = 0.04 * fontSize;
    final limit = unit.box.width * 0.45;
    var d = 0.0;
    for (; d < limit; d += step) {
      final cx = x + direction * (d + step / 2);
      var bare = true;
      for (var y = unit.ink.top + step / 2; y < unit.ink.bottom; y += step) {
        if (y >= band.top - slack && y <= band.bottom + slack) continue;
        if (coverage(unit, cx, y) > 0.12) {
          bare = false;
          break;
        }
      }
      if (!bare) break;
    }
    return d;
  }

  static List<TextRange> _mergeEmpty(List<TextRange> ranges, List<int> empty) {
    final inkless = {for (final e in empty) ranges[e].start};
    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    final out = <TextRange>[];
    int? carry;
    for (final r in sorted) {
      if (inkless.contains(r.start)) {
        // Into the cluster before it, which holds the ligature, or else the one after.
        if (out.isNotEmpty && out.last.end == r.start) {
          out[out.length - 1] = TextRange(start: out.last.start, end: r.end);
        } else {
          carry ??= r.start;
        }
        continue;
      }
      out.add(carry == null ? r : TextRange(start: carry, end: r.end));
      carry = null;
    }
    return out;
  }

  static Rect _box(ui.Paragraph p, TextRange r) {
    final boxes = p.getBoxesForRange(r.start, r.end);
    if (boxes.isEmpty) return Rect.zero;
    var rect = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      rect = rect.expandToInclude(b.toRect());
    }
    return rect;
  }

  static TextDirection _guessDirection(String text) {
    for (final c in text.runes) {
      if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFEFC)) return TextDirection.rtl;
      if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c >= 0x0900) return TextDirection.ltr;
    }
    return TextDirection.ltr;
  }
}

/// The run with only [range] visible; for the package's own use.
ui.Paragraph isolatedParagraph(ShapedText text, TextRange range) => text.isolated(range);

ui.Paragraph _paragraph(String text, TextStyle style, TextDirection direction, {TextRange? only}) {
  final builder = ui.ParagraphBuilder(style.getParagraphStyle(textDirection: direction, maxLines: 1));
  if (only == null) {
    builder
      ..pushStyle(style.getTextStyle())
      ..addText(text);
  } else {
    final clear = style.foreground != null
        ? style.copyWith(foreground: Paint()..color = const Color(0x00000000))
        : style.copyWith(color: const Color(0x00000000));
    void add(TextStyle s, int from, int to) {
      if (to <= from) return;
      builder
        ..pushStyle(s.getTextStyle())
        ..addText(text.substring(from, to))
        ..pop();
    }

    add(clear, 0, only.start);
    add(style, only.start, only.end);
    add(clear, only.end, text.length);
  }
  // Laid out once to find its width, then again at that width: right-to-left text on an endless line starts at
  // infinity.
  final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  return paragraph..layout(ui.ParagraphConstraints(width: paragraph.maxIntrinsicWidth.ceilToDouble()));
}

/// The run's clusters drawn at some density, each alone in its own cell.
class TextAtlas {
  TextAtlas._(this.image, this.density, this._cells, this._origins, this._owner);

  /// The cells.
  final ui.Image image;

  /// Texels per logical pixel.
  final double density;

  final List<Rect> _cells;
  final List<Offset> _origins;
  final Object _owner;

  /// Whether this atlas was drawn from [text] (its own, or by its [ShapedText.drawAtlas]).
  bool isFor(ShapedText text) => identical(_owner, text.atlas._owner);

  /// Where the flat point ([x], [y]) of cluster [unit] (an index into [ShapedText.units]) is in [image], in texels.
  Offset texel(int unit, double x, double y) => Offset(
        _cells[unit].left + (x - _origins[unit].dx) * density,
        _cells[unit].top + (y - _origins[unit].dy) * density,
      );

  ImageShader? _shader;
  FilterQuality? _quality;

  /// A shader of [image] in texels, for a [Paint]: made once and kept while the atlas lives. (On the web, disposing an
  /// image shader disposes its image too, so one made and disposed for each paint would take the atlas with it.)
  ImageShader shader(FilterQuality quality) {
    if (_shader == null || _quality != quality) {
      _shader = ImageShader(image, TileMode.decal, TileMode.decal, _identity, filterQuality: quality);
      _quality = quality;
    }
    return _shader!;
  }

  static final _identity = Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  /// Frees the image.
  void dispose() {
    // On the web the shader owns the image, and disposing it disposes both.
    if (kIsWeb && _shader != null) {
      _shader!.dispose();
    } else {
      _shader?.dispose();
      image.dispose();
    }
    _shader = null;
  }
}

/// One grapheme cluster of the run.
class TextUnit {
  TextUnit._(this.range, this.box, this.cell, this.cellOrigin);

  /// Its code units in the text.
  final TextRange range;

  /// Its advance box in the flat run.
  final Rect box;

  /// Where its ink is in the flat run. It can overhang the box, like an Arabic tail.
  Rect ink = Rect.zero;

  /// Its cell in [ShapedText.atlas], in texels.
  final Rect cell;

  /// The flat point drawn at that cell's top-left.
  final Offset cellOrigin;

  /// The middle of its box: where it's anchored when placed.
  double get anchor => box.center.dx;
}

/// Two clusters side by side in the flat run, [left] and [right] (indices into [ShapedText.units]), with the boundary
/// [x] between them.
class UnitPair {
  UnitPair._(
    this.left,
    this.right,
    this.x,
    this.touching, {
    this.joins = false,
    this.inBand = false,
    this.crossing = const [],
    this.slope = 0,
    this.leftBare = 0,
    this.rightBare = 0,
  });

  /// Indices of the two clusters in [ShapedText.units].
  final int left, right;

  /// The boundary between them.
  final double x;

  /// Whether their boxes meet, with no space between.
  final bool touching;

  /// Whether a stroke runs from one into the other.
  final bool joins;

  /// Whether that stroke crosses in the joining rows ([ShapedText.band]).
  final bool inBand;

  /// The rows where the joining stroke crosses the boundary, as (top, bottom) in the flat run.
  final List<(double, double)> crossing;

  /// How steeply the joining stroke crosses the boundary: its drop (y runs down) for each pixel to the right. Naskh's
  /// baseline and the Indic headline cross flat; Nastaliq's joins and a script hand's slope.
  final double slope;

  /// Whether the join can be drawn out along a curve, as a tatweel draws out an Arabic join: its stroke crosses flat,
  /// in the joining rows.
  bool get canDrawOut => joins && inBand && slope.abs() < 0.2;

  /// How much of the joining stroke on each side is bare: only stroke, no letter above or below it.
  final double leftBare, rightBare;
}

/// The rows a script's letters join on, in the flat run: y down from the top of the line.
class ConnectionBand {
  /// The rows from [top] to [bottom].
  const ConnectionBand(this.top, this.bottom);

  /// The band's edges.
  final double top, bottom;

  /// Its middle: the line the letters join along.
  double get center => (top + bottom) / 2;

  @override
  String toString() => 'ConnectionBand(${top.toStringAsFixed(1)}..${bottom.toStringAsFixed(1)})';
}

/// Which rows a script's letters join on.
class ConnectionLine {
  /// Found from the run: the rows where most joining strokes cross from one letter into the next.
  const ConnectionLine.auto()
      : _low = null,
        _high = null;

  /// Fixed rows, from [low] to [high] em above the baseline. The Arabic baseline stroke is about 0 to 0.1 em; the
  /// Devanagari headline about 0.62 to 0.72.
  const ConnectionLine.between(double low, double high)
      : _low = low,
        _high = high;

  final double? _low, _high;

  @override
  bool operator ==(Object other) => other is ConnectionLine && other._low == _low && other._high == _high;

  @override
  int get hashCode => Object.hash(_low, _high);

  ConnectionBand? _resolve(double baseline, double fontSize) {
    if (_low == null || _high == null) return null;
    return ConnectionBand(baseline - _high * fontSize, baseline - _low * fontSize);
  }
}

class _Atlas {
  _Atlas(this.image, this.alpha, this.units);

  final ui.Image image;
  final Uint8List alpha;
  final List<TextUnit> units;

  // Room round each cluster's box for ink that overhangs it.
  static double marginX(double fontSize) => 1.5 * fontSize;
  static double marginY(double fontSize) => 0.6 * fontSize;

  static Future<_Atlas> draw(
    String text,
    TextStyle style,
    TextDirection direction,
    List<TextRange> ranges,
    List<Rect> boxes,
    double width,
    double height,
    double fontSize,
    double scale,
  ) async {
    const maxRow = 4096.0;
    final mx = marginX(fontSize), my = marginY(fontSize);
    final units = <TextUnit>[];
    var x = 0.0, y = 0.0, rowHeight = 0.0, atlasWidth = 0.0;
    for (var i = 0; i < ranges.length; i++) {
      final flat = Rect.fromLTRB(
        math.max(-mx, boxes[i].left - mx),
        -my,
        math.min(width + mx, boxes[i].right + mx),
        height + my,
      );
      final w = (flat.width * scale).ceil() + 2.0, h = (flat.height * scale).ceil() + 2.0;
      if (x > 0 && x + w > maxRow) {
        x = 0;
        y += rowHeight;
        rowHeight = 0;
      }
      units.add(TextUnit._(ranges[i], boxes[i], Rect.fromLTWH(x + 1, y + 1, w - 2, h - 2), flat.topLeft));
      x += w;
      rowHeight = math.max(rowHeight, h);
      atlasWidth = math.max(atlasWidth, x);
    }
    final atlasHeight = y + rowHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final u in units) {
      canvas
        ..save()
        ..translate(u.cell.left, u.cell.top)
        ..clipRect(Rect.fromLTWH(0, 0, u.cell.width, u.cell.height))
        ..scale(scale)
        ..translate(-u.cellOrigin.dx, -u.cellOrigin.dy)
        ..drawParagraph(_paragraph(text, style, direction, only: u.range), Offset.zero)
        ..restore();
    }
    final image = await recorder.endRecording().toImage(atlasWidth.ceil(), atlasHeight.ceil());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    final aw = image.width;
    final alpha = Uint8List(aw * image.height);
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = bytes[i * 4 + 3];
    }

    // Each cluster's ink.
    for (final u in units) {
      var l = 1 << 30, t = 1 << 30, r = -1, b = -1;
      for (var ty = u.cell.top.toInt(); ty < u.cell.bottom; ty++) {
        final row = ty * aw;
        for (var tx = u.cell.left.toInt(); tx < u.cell.right; tx++) {
          if (alpha[row + tx] > 4) {
            if (tx < l) l = tx;
            if (tx > r) r = tx;
            if (ty < t) t = ty;
            if (ty > b) b = ty;
          }
        }
      }
      if (r >= 0) {
        u.ink = Rect.fromLTRB(
          u.cellOrigin.dx + (l - u.cell.left) / scale,
          u.cellOrigin.dy + (t - u.cell.top) / scale,
          u.cellOrigin.dx + (r + 1 - u.cell.left) / scale,
          u.cellOrigin.dy + (b + 1 - u.cell.top) / scale,
        );
      }
    }
    return _Atlas(image, alpha, units);
  }
}
