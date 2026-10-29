// Measures how much softer the mesh-drawn text is than the same letters drawn natively, as the view zooms in, both
// from one atlas and as TextOnPath draws it (an atlas redrawn for the zoom, or traced outlines), and writes
// doc/sharpness.md and doc/images/sharpness.png.
//
// Run from the package's folder:
//   flutter test tool/sharpness_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const fontSize = 32.0;
const text = 'शिरोरेखा जुड़ी';
const zooms = [1.0, 2.0, 4.0, 8.0];
const densities = [1.0, 2.0, 4.0, 8.0]; // Atlas texels per logical pixel.
const widgetZooms = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];
const budget = 16 << 20; // TextOnPath.maxAtlasTexels's default.

/// The same placement drawn natively: each cluster's own paragraph (the rest of the run transparent), turned and moved
/// exactly as rigid placement moves it. Glyphs rasterised at the final scale: the sharpest the text can be.
void drawNative(Canvas canvas, TextOnPathPlacement p, TextStyle style) {
  final shaped = p.text;
  for (var i = 0; i < shaped.units.length; i++) {
    final u = shaped.units[i];
    final origin = p.map(i, u.anchor, shaped.baseline);
    final along = p.map(i, u.anchor + 1, shaped.baseline) - origin;
    final builder = ui.ParagraphBuilder(style.getParagraphStyle(textDirection: shaped.textDirection, maxLines: 1));
    void add(int from, int to, bool on) {
      if (to <= from) return;
      builder
        ..pushStyle((on ? style : style.copyWith(color: const Color(0x00000000))).getTextStyle())
        ..addText(shaped.text.substring(from, to))
        ..pop();
    }

    add(0, u.range.start, false);
    add(u.range.start, u.range.end, true);
    add(u.range.end, shaped.text.length, false);
    final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    paragraph.layout(ui.ParagraphConstraints(width: paragraph.maxIntrinsicWidth.ceilToDouble()));
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..rotate(math.atan2(along.dy, along.dx))
      ..translate(-u.anchor, -shaped.baseline)
      ..drawParagraph(paragraph, Offset.zero)
      ..restore();
  }
}

Future<Uint8List> render(Rect frame, double zoom, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(zoom)
    ..translate(-frame.left, -frame.top);
  draw(canvas);
  final image = await recorder.endRecording().toImage((frame.width * zoom).ceil(), (frame.height * zoom).ceil());
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
  return Uint8List.fromList([for (var i = 3; i < bytes.length; i += 4) bytes[i]]);
}

/// Pixels on an edge: neither clear nor solid.
int edgePixels(Uint8List alpha) => alpha.where((a) => a > 25 && a < 230).length;

/// Mean difference from [reference], as a share of its ink.
double difference(Uint8List alpha, Uint8List reference) {
  var d = 0, ink = 0;
  for (var i = 0; i < alpha.length; i++) {
    d += (alpha[i] - reference[i]).abs();
    ink += reference[i];
  }
  return d / ink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sharpness', () async {
    final bytes = File('example/fonts/NotoSansDevanagari.ttf').readAsBytesSync();
    await (FontLoader('Deva')..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    const style = TextStyle(fontFamily: 'Deva', fontSize: fontSize, color: Color(0xff000000));
    final curve = PathCurve.arc(Offset.zero, 4 * fontSize);
    String cell(Uint8List drawn, Uint8List native) =>
        '${(edgePixels(drawn) / edgePixels(native)).toStringAsFixed(2)}× (${(100 * difference(drawn, native)).round()}%)';

    // A small window round one join, where the rows meet.
    final probe = await ShapedText.layout(text, style, scale: 2);
    final rigidProbe = TextOnPathPlacement(probe, curve, mode: TextOnPathMode.rigid);
    final pair = probe.neighbours.firstWhere((p) => p.joins);
    final window = Rect.fromCenter(
      center: rigidProbe.map(pair.left, pair.x, probe.band!.center),
      width: 1.6 * fontSize,
      height: 1.6 * fontSize,
    );

    // 1. One atlas, magnified.
    final rows = <String>[];
    for (final zoom in zooms) {
      final cells = <String>[];
      final native = await render(window, zoom, (c) => drawNative(c, rigidProbe, style));
      for (final density in densities) {
        final shaped = await ShapedText.layout(text, style, scale: density);
        final rigid = TextOnPathPlacement(shaped, curve, mode: TextOnPathMode.rigid);
        cells.add(cell(await render(window, zoom, (c) => rigid.paint(c)), native));
        shaped.dispose();
      }
      rows.add('| ${zoom.round()}× | ${cells.join(' | ')} |');
    }

    // 2. What TextOnPath draws: one atlas as shaped (2 texels a pixel at rest), an atlas drawn again for the zoom (or
    // outlines past the budget), and outlines.
    final outlines = await TextOutlines.trace(probe);
    final widgetRows = <String>[];
    final crops = <(String, ui.Image)>[];
    for (final zoom in widgetZooms) {
      final native = await render(window, zoom, (c) => drawNative(c, rigidProbe, style));
      final fixed = await render(window, zoom, (c) => rigidProbe.paint(c));
      final density = TextOnPath.atlasDensityFor(zoom);
      final texels = probe.texelsAt(density);
      final String auto;
      if (texels > budget) {
        auto = '${cell(await render(window, zoom, (c) => rigidProbe.paintOutlines(c, outlines)), native)}, outlines';
      } else {
        final atlas = await probe.drawAtlas(density);
        auto = '${cell(await render(window, zoom, (c) => rigidProbe.paint(c, atlas: atlas)), native)}, atlas '
            '${density.toStringAsFixed(density < 4 ? 1 : 0)} texel/px, ${(texels * 4 / (1 << 20)).toStringAsFixed(1)} MB';
        if (zoom == 16) crops.add(('redrawn', await _image(window, zoom, (c) => rigidProbe.paint(c, atlas: atlas))));
        atlas.dispose();
      }
      final vector = await render(window, zoom, (c) => rigidProbe.paintOutlines(c, outlines));
      widgetRows
          .add('| ${zoom < 1 ? zoom : zoom.round()}× | ${cell(fixed, native)} | $auto | ${cell(vector, native)} |');
      if (zoom == 16) {
        crops.insert(0, ('one atlas', await _image(window, zoom, (c) => rigidProbe.paint(c))));
        crops.add(('outlines', await _image(window, zoom, (c) => rigidProbe.paintOutlines(c, outlines))));
        crops.add(('native', await _image(window, zoom, (c) => drawNative(c, rigidProbe, style))));
      }
    }
    probe.dispose();

    // The crops side by side, a quarter of each.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var x = 0.0;
    final side = crops.first.$2.width / 2;
    for (final (_, image) in crops) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(image.width / 4, image.height / 4, side, side),
        Rect.fromLTWH(x, 0, side, side),
        Paint()..filterQuality = FilterQuality.none,
      );
      x += side + 10;
    }
    final sheet = await recorder.endRecording().toImage((x - 10).ceil(), side.ceil());
    File('doc/images/sharpness.png')
        .writeAsBytesSync((await sheet.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());

    final out = StringBuffer()
      ..writeln('# Sharpness')
      ..writeln()
      ..writeln('Written by `flutter test tool/sharpness_test.dart`.')
      ..writeln()
      ..writeln('The text is shaped by Flutter\'s paragraph engine and drawn into an atlas, one cluster at a time; the '
          'mesh samples that raster. So `TextOnPath` keeps it sharp two ways: it draws the atlas again for the scale '
          'the text is shown at (the zoom of every transform above it, times the screen\'s pixel ratio), and past a '
          'memory budget it draws traced outlines instead.')
      ..writeln()
      ..writeln('Each measurement draws a window round one join of a Hindi phrase at ${fontSize.round()} px, placed '
          'rigidly on a circle of radius 4 em: rigid, so the same letters can also be drawn natively, as vectors, '
          'under exactly the same rotation. A cell gives the drawn edges\' width against native ones (pixels neither '
          'clear nor solid, as a ratio: 1× matches native, above is softer, below is harder, that is aliased) and, in '
          'brackets, the mean difference from native as a share of the ink.')
      ..writeln()
      ..writeln('## What `TextOnPath` draws')
      ..writeln()
      ..writeln('Zoom in screen pixels to each logical pixel (a screen at device pixel ratio 2 doubles it). *One '
          'atlas* is `TextOnPathRendering.raster`: two texels a pixel, drawn once. *Auto* is the default: an atlas '
          'drawn again at two texels a screen pixel (rounded up to a power of √2), or outlines once that atlas would '
          'pass 16 M texels (64 MB). *Outlines* is `TextOnPathRendering.vector`.')
      ..writeln()
      ..writeln('| Zoom | One atlas | Auto | Outlines |')
      ..writeln('|---|---:|---:|---:|');
    widgetRows.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('![At 16× zoom: one atlas, an atlas drawn for the zoom, outlines, native text](images/sharpness.png)')
      ..writeln()
      ..writeln('*At 16× zoom, left to right: one atlas, the atlas drawn again for the zoom, traced outlines, and '
          'native text. (Rigid placement, so the native text can be drawn the same way; hence the opening in the '
          'headline.)*')
      ..writeln()
      ..writeln('## One atlas, magnified')
      ..writeln()
      ..writeln('*Texel/px* is atlas texels per logical pixel.')
      ..writeln()
      ..writeln('| Zoom | ${densities.map((d) => 'Atlas ${d.round()} texel/px').join(' | ')} |')
      ..writeln('|---|${densities.map((_) => '---:').join('|')}|');
    rows.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('- **Zooming past the atlas.** Edges match native best at about two atlas texels per screen pixel. At '
          'one texel per pixel they come out about 1.7 times as wide, and every further doubling of the zoom doubles '
          'them again. Drawing the atlas again for the zoom fixes it, at a cost in memory that grows with the square '
          'of the zoom: the atlas cells are cropped to each cluster\'s ink, which keeps it to a few MB up to about 8×.')
      ..writeln('- **Zooming out past it.** With many texels to each pixel and no mip levels, edges turn hard and '
          'jagged: 8 texels per pixel at 1× gives edges a fifth as wide as native. Auto draws a coarser atlas when '
          'zoomed out, too.')
      ..writeln('- **Where the mesh stretches.** Stretching spreads the same texels over more pixels. Plain warp '
          'stretches every letter on the outside of a bend by 1 + height × curvature: the top of a Devanagari letter '
          'on a 3 em circle by about a quarter. Joined placement keeps letters rigid; only the joining rows bend '
          '(stretched by about 1%), and a widened join is bridged by repeating the stroke\'s cross-section along the '
          'curve, so it doesn\'t soften across the stroke.')
      ..writeln('- **Turning it at all.** Even at two texels per pixel, sampling a turned raster differs by 5–10% from '
          'glyphs rasterised in place: a little softer and heavier at the edges.')
      ..writeln()
      ..writeln('## Outlines')
      ..writeln()
      ..writeln(
          'Flutter doesn\'t hand back glyph outlines from a paragraph, and shaping outside it (HarfBuzz and a font '
          'parser) would mean a second shaper to keep in step with the first. So `TextOutlines.trace` traces them: '
          'each cluster drawn alone at 8 texels per logical pixel, its edge (where coverage crosses one half) '
          'followed by marching squares and simplified to within 0.02 px. That takes tens of milliseconds for a '
          'phrase and gives about a thousand points. The same mapping as the mesh carries each point onto the curve, '
          'with edges cut to a pixel first so they bend with it; a bridge is the stroke\'s cross-section, read off '
          'the outline, swept along the curve.')
      ..writeln()
      ..writeln('They make `TextOnPathPlacement.toSvg` and `toPdf` possible, and stay sharp at any zoom. The edges are '
          'the font\'s own to a few hundredths of a pixel at the text\'s size, so at very high zoom (past about 30×) '
          'the polygon behind a curve starts to show; tracing at a higher density pushes that further. They aren\'t '
          'the font\'s exact Bézier curves, and hinting and the text renderer\'s own antialiasing tweaks are gone.')
      ..writeln();
    File('doc/sharpness.md').writeAsStringSync(out.toString());
    stdout.write(out);
  });
}

Future<ui.Image> _image(Rect frame, double zoom, void Function(Canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(zoom)
    ..translate(-frame.left, -frame.top);
  canvas.drawRect(frame, Paint()..color = const Color(0xffffffff));
  draw(canvas);
  return recorder.endRecording().toImage((frame.width * zoom).ceil(), (frame.height * zoom).ceil());
}
