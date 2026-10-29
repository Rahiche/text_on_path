// Draws the paper's figures into doc/figures/:
//   comparison.png and comparison.svg: Hindi and Urdu on a circle, rigid placement cluster by cluster, plain warp and
//     joined placement side by side;
//   comparison_joins.png: for each, the join rigid placement opens widest, magnified in each placement;
//   mesh.png: three clusters' meshes, flat and placed, the joining rows bent and the rest rigid.
//
// Run from the package's folder:
//   flutter test tool/figures_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const ink = Color(0xff1d1a16);
const teal = Color(0xff0f6e5c);
const fontSize = 48.0;

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// Where the placed text's ink reaches, traced round each cluster's ink box.
Rect placedBounds(TextOnPathPlacement p) {
  Rect? box;
  for (var i = 0; i < p.text.units.length; i++) {
    final r = p.text.units[i].ink;
    if (r.isEmpty) continue;
    for (var k = 0; k <= 8; k++) {
      final f = k / 8;
      for (final o in [
        p.map(i, r.left + r.width * f, r.top),
        p.map(i, r.left + r.width * f, r.bottom),
        p.map(i, r.left, r.top + r.height * f),
        p.map(i, r.right, r.top + r.height * f),
      ]) {
        box = box == null ? Rect.fromPoints(o, o) : box.expandToInclude(Rect.fromPoints(o, o));
      }
    }
  }
  return box!;
}

ui.Paragraph label(String text, double size, {Color color = ink, FontWeight weight = FontWeight.w600}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Deva', fontSize: size, fontWeight: weight))
    ..pushStyle(ui.TextStyle(color: color, fontFamily: 'Deva', fontSize: size, fontWeight: weight))
    ..addText(text);
  return b.build()..layout(const ui.ParagraphConstraints(width: 2000));
}

Future<void> savePng(ui.Picture picture, int w, int h, String path) async {
  final image = await picture.toImage(w, h);
  File(path).writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
}

String svgPath(List<Float64List> loops, Offset shift, double scale) {
  final d = StringBuffer();
  String n(double v) => v.toStringAsFixed(2);
  for (final loop in loops) {
    for (var k = 0; k < loop.length; k += 2) {
      d.write('${k == 0 ? 'M' : 'L'}${n((loop[k] + shift.dx) * scale)} ${n((loop[k + 1] + shift.dy) * scale)}');
    }
    d.write('Z');
  }
  return d.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Directory('doc/figures').createSync(recursive: true);
    await loadFont('Deva', 'NotoSansDevanagari.ttf');
    await loadFont('Nastaliq', 'NotoNastaliqUrdu.ttf');
  });

  test('comparison', () async {
    const modes = [TextOnPathMode.rigid, TextOnPathMode.warp, TextOnPathMode.joined];
    const titles = ['Rigid, cluster by cluster', 'Plain warp', 'Joined'];
    final rows = [('Hindi', 'Deva', 'शिरोरेखा जुड़ी रहती है'), ('Urdu', 'Nastaliq', 'بہت شکریہ')];
    final curve = PathCurve.arc(Offset.zero, 3 * fontSize);

    // Every panel the same size: the widest and tallest text, and a margin.
    final shaped = <ShapedText>[];
    final frames = <Rect>[];
    for (final (_, family, text) in rows) {
      final s = await ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: fontSize, color: ink));
      shaped.add(s);
      var box = placedBounds(TextOnPathPlacement(s, curve, mode: modes.first));
      for (final mode in modes.skip(1)) {
        box = box.expandToInclude(placedBounds(TextOnPathPlacement(s, curve, mode: mode)));
      }
      frames.add(box.inflate(10));
    }
    final panelW = frames.fold(0.0, (m, f) => math.max(m, f.width));
    const left = 96.0, top = 40.0, gap = 18.0;
    final width = left + 3 * panelW + 2 * gap + 8;
    final scale = 2000 / width; // About 2000 pixels wide.
    final heights = [for (final f in frames) f.height];
    final height = top + heights.fold(0.0, (a, h) => a + h) + gap * (rows.length - 1) + 8;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xffffffff));
    final svg = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${(width * scale).round()} '
          '${(height * scale).round()}" width="${(width * scale).round()}" height="${(height * scale).round()}">')
      ..writeln('<rect width="100%" height="100%" fill="#ffffff"/>');
    for (var c = 0; c < modes.length; c++) {
      final x = left + c * (panelW + gap);
      final title = label(titles[c], 15);
      canvas.drawParagraph(title, Offset(x + (panelW - title.maxIntrinsicWidth) / 2, 10));
      svg.writeln('<text x="${((x + panelW / 2) * scale).toStringAsFixed(1)}" y="${(27 * scale).toStringAsFixed(1)}" '
          'font-family="Helvetica, Arial, sans-serif" font-size="${(15 * scale).toStringAsFixed(1)}" font-weight="600" '
          'text-anchor="middle" fill="#1d1a16">${titles[c]}</text>');
    }
    var y = top;
    for (var r = 0; r < rows.length; r++) {
      final s = shaped[r];
      final frame = frames[r];
      final name = label(rows[r].$1, 15);
      canvas.drawParagraph(name, Offset(8, y + frame.height / 2 - name.height / 2));
      svg.writeln(
          '<text x="${(8 * scale).toStringAsFixed(1)}" y="${((y + frame.height / 2 + 5) * scale).toStringAsFixed(1)}" '
          'font-family="Helvetica, Arial, sans-serif" font-size="${(15 * scale).toStringAsFixed(1)}" font-weight="600" '
          'fill="#1d1a16">${rows[r].$1}</text>');
      // Two atlas texels to each pixel of the picture: as sharp as the text renderer itself.
      final atlas = await s.drawAtlas(2 * scale);
      final outlines = await TextOutlines.trace(s);
      for (var c = 0; c < modes.length; c++) {
        final x = left + c * (panelW + gap);
        final shift = Offset(x + (panelW - frame.width) / 2 - frame.left, y - frame.top);
        final placement = TextOnPathPlacement(s, curve, mode: modes[c]);
        canvas
          ..save()
          ..clipRect(Rect.fromLTWH(x, y, panelW, frame.height))
          ..translate(shift.dx, shift.dy)
          ..drawPath(
            curve.toPath(),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0x24000000),
          );
        placement.paint(canvas, atlas: atlas);
        canvas.restore();
        for (final shape in placement.outlineShapes(outlines)) {
          svg.writeln('<path fill="#1d1a16" fill-rule="evenodd" d="${svgPath(shape, shift, scale)}"/>');
        }
      }
      atlas.dispose();
      y += frame.height + gap;
    }
    svg.writeln('</svg>');
    await savePng(
        recorder.endRecording(), (width * scale).round(), (height * scale).round(), 'doc/figures/comparison.png');
    File('doc/figures/comparison.svg').writeAsStringSync(svg.toString());

    // Close-ups: for each script, the join rigid placement opens widest, magnified at the same spot in each placement.
    const zoom = 6.0, window = 1.3 * fontSize, pad = 14.0, head = 34.0, side = 70.0;
    final closeW = side + 3 * window * zoom + 4 * pad, closeH = head + rows.length * (window * zoom + pad) + pad;
    final close = ui.PictureRecorder();
    final cc = Canvas(close)..drawRect(Rect.fromLTWH(0, 0, closeW, closeH), Paint()..color = const Color(0xffffffff));
    for (var c = 0; c < modes.length; c++) {
      final t = label(titles[c], 22);
      cc.drawParagraph(
          t, Offset(side + pad + c * (window * zoom + pad) + (window * zoom - t.maxIntrinsicWidth) / 2, 4));
    }
    for (var r = 0; r < rows.length; r++) {
      final sh = shaped[r];
      final rigid = TextOnPathPlacement(sh, curve, mode: TextOnPathMode.rigid);
      UnitPair? worst;
      var worstY = 0.0, widest = -1.0;
      for (final p in sh.neighbours) {
        if (!p.joins) continue;
        for (final (y0, y1) in p.crossing) {
          for (final yy in [y0 + 0.5, (y0 + y1) / 2, y1 - 0.5]) {
            final d = (rigid.rendered(p.left, p.x, yy) - rigid.rendered(p.right, p.x, yy)).distance;
            if (d > widest) {
              widest = d;
              worst = p;
              worstY = (y0 + y1) / 2;
            }
          }
        }
      }
      final name = label(rows[r].$1, 22);
      final top = head + r * (window * zoom + pad);
      cc.drawParagraph(name, Offset(6, top + window * zoom / 2 - name.height / 2));
      final atlas = await sh.drawAtlas(2 * zoom);
      for (var c = 0; c < modes.length; c++) {
        final placement = TextOnPathPlacement(sh, curve, mode: modes[c]);
        final spot =
            (placement.rendered(worst!.left, worst.x, worstY) + placement.rendered(worst.right, worst.x, worstY)) / 2;
        final x = side + pad + c * (window * zoom + pad);
        cc
          ..save()
          ..clipRect(Rect.fromLTWH(x, top, window * zoom, window * zoom))
          ..drawRect(Rect.fromLTWH(x, top, window * zoom, window * zoom), Paint()..color = const Color(0xfff7f3ec))
          ..translate(x + window * zoom / 2, top + window * zoom / 2)
          ..scale(zoom)
          ..translate(-spot.dx, -spot.dy);
        placement.paint(cc, atlas: atlas);
        cc.restore();
      }
      atlas.dispose();
    }
    await savePng(close.endRecording(), closeW.round(), closeH.round(), 'doc/figures/comparison_joins.png');
    for (final s in shaped) {
      s.dispose();
    }
  });

  test('mesh', () async {
    final s = await ShapedText.layout(
      'शिरोरेखा जुड़ी',
      const TextStyle(fontFamily: 'Deva', fontSize: fontSize, color: ink),
    );
    // Three clusters joined in a row, the middle one the widest such.
    var middle = -1;
    for (var i = 1; i + 1 < s.units.length; i++) {
      if (!s.neighbours[i - 1].joins || !s.neighbours[i].joins) continue;
      if (middle < 0 || s.units[i].ink.width > s.units[middle].ink.width) middle = i;
    }
    final shown = [middle - 1, middle, middle + 1];
    // A tight bend, so the bend shows; the middle cluster at the top of the circle.
    final curve = PathCurve.arc(Offset.zero, 1.6 * fontSize);
    final u = s.units[middle];
    final placement = TextOnPathPlacement(
      s,
      curve,
      mode: TextOnPathMode.joined,
      position: 0.5 - (u.anchor - s.width / 2) / curve.length,
    );
    final outlines = await TextOutlines.trace(s, density: 16);
    const scale = 5.0, step = 0.07 * fontSize;
    final colours = [const Color(0xffb0702a), const Color(0xff5a5f9e), const Color(0xffa1432c)];

    var flatBox = s.units[shown.first].ink;
    for (final i in shown) {
      flatBox = flatBox.expandToInclude(s.units[i].ink);
    }
    final flatFrame = flatBox.inflate(16);
    Rect? placedBox;
    for (final i in shown) {
      final ink = s.units[i].ink;
      for (final o in [ink.topLeft, ink.topRight, ink.bottomLeft, ink.bottomRight, ink.topCenter, ink.bottomCenter]) {
        final p = placement.map(i, o.dx, o.dy);
        placedBox = placedBox == null ? Rect.fromPoints(p, p) : placedBox.expandToInclude(Rect.fromPoints(p, p));
      }
    }
    final placedFrame = placedBox!.inflate(16);
    const gap = 40.0;
    final width = (flatFrame.width + placedFrame.width) * scale + gap;
    final height = math.max(flatFrame.height, placedFrame.height) * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xffffffff));

    void fill(List<Float64List> loops, Offset Function(Offset) at, Color color) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final loop in loops) {
        for (var k = 0; k < loop.length; k += 2) {
          final o = at(Offset(loop[k], loop[k + 1]));
          k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        path.close();
      }
      canvas.drawPath(path, Paint()..color = color);
    }

    // Each shown cluster's grid: rows in the joining rows teal and heavy, the rest in the cluster's own colour.
    void grids(Offset Function(int unit, double x, double y) at) {
      for (final (k, i) in shown.indexed) {
        final g = s.units[i].ink.inflate(2);
        final nx = (g.width / step).ceil(), ny = (g.height / step).ceil();
        for (var r = 0; r <= ny; r++) {
          final y = g.top + g.height * r / ny;
          final w = placement.rowWeight(y);
          final path = Path();
          for (var c = 0; c <= nx * 6; c++) {
            final o = at(i, g.left + g.width * c / (nx * 6), y);
            c == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w > 0.5 ? 2.4 : 1.1
              ..color = Color.lerp(colours[k].withValues(alpha: 0.55), teal, w)!,
          );
        }
        for (var c = 0; c <= nx; c++) {
          final x = g.left + g.width * c / nx;
          final path = Path();
          for (var r = 0; r <= ny * 6; r++) {
            final o = at(i, x, g.top + g.height * r / (ny * 6));
            r == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.1
              ..color = colours[k].withValues(alpha: 0.55),
          );
        }
      }
    }

    // Left: flat, the joining rows shaded.
    Offset flat(Offset p) => (p - flatFrame.topLeft) * scale;
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, flatFrame.width * scale, height));
    final band = s.band!;
    canvas.drawRect(
      Rect.fromPoints(flat(Offset(flatFrame.left, band.top)), flat(Offset(flatFrame.right, band.bottom))),
      Paint()..color = teal.withValues(alpha: 0.12),
    );
    for (var i = 0; i < s.units.length; i++) {
      fill(outlines.contours[i], flat, shown.contains(i) ? ink.withValues(alpha: 0.85) : const Color(0x1f000000));
    }
    grids((i, x, y) => flat(Offset(x, y)));
    canvas.restore();

    // Right: placed on the curve.
    final origin = Offset(flatFrame.width * scale + gap, 0);
    Offset placed(Offset p) => origin + (p - placedFrame.topLeft) * scale;
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(origin.dx, 0, placedFrame.width * scale, height));
    final circle = Path();
    for (var k = 0; k <= 400; k++) {
      final o = placed(curve.pointAt(curve.length * k / 400));
      k == 0 ? circle.moveTo(o.dx, o.dy) : circle.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x40000000),
    );
    for (var i = 0; i < s.units.length; i++) {
      fill(
        placement.outlineOf(outlines, i),
        placed,
        shown.contains(i) ? ink.withValues(alpha: 0.85) : const Color(0x1f000000),
      );
    }
    grids((i, x, y) => placed(placement.map(i, x, y)));
    canvas.restore();
    canvas.drawRect(
        Rect.fromLTWH(flatFrame.width * scale + gap / 2 - 1, 0, 2, height), Paint()..color = const Color(0xffe4ddd1));
    await savePng(recorder.endRecording(), width.round(), height.round(), 'doc/figures/mesh.png');
    stdout.writeln(
        'mesh: clusters ${[for (final i in shown) s.text.substring(s.units[i].range.start, s.units[i].range.end)]}, '
        'band ${s.band}, baseline ${s.baseline.toStringAsFixed(1)}');
    s.dispose();
  });
}
