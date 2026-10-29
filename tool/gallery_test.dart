// Draws the README's gallery into doc/images/: gallery_<script>.png, each script's phrase on an arc and an S-curve,
// and seals.png, every phrase fitted round a seal.
//
// Run from the package's folder:
//   flutter test tool/gallery_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const ink = Color(0xff1d1a16);
const paper = Color(0xfffbf8f2);
const muted = Color(0xff7a7268);
const sealRed = Color(0xff9c1d15);
const scale = 1.5; // Pixels of the picture to each logical pixel.

/// (name, family, font file, text, meaning, fit)
const samples = <(String, String, String, String, String, TextOnPathFit)>[
  ('Arabic', 'Naskh', 'NotoNaskhArabic.ttf', 'الحروف تبقى متصلة', 'The letters stay connected', TextOnPathFit.kashida),
  ('Persian', 'Naskh', 'NotoNaskhArabic.ttf', 'خیلی ممنون', 'Thank you very much', TextOnPathFit.kashida),
  ('Urdu', 'Nastaliq', 'NotoNastaliqUrdu.ttf', 'بہت شکریہ', 'Thank you very much', TextOnPathFit.spacing),
  (
    'Hindi',
    'Deva',
    'NotoSansDevanagari.ttf',
    'शिरोरेखा जुड़ी रहती है',
    'The headline stays joined',
    TextOnPathFit.tracking
  ),
  (
    'Bengali',
    'Beng',
    'NotoSansBengali.ttf',
    'বাংলা লিপির মাত্রা',
    'The headline of Bengali script',
    TextOnPathFit.tracking
  ),
  ('Latin script', 'Dancing', 'DancingScript.ttf', 'Handwriting stays joined', 'Dancing Script', TextOnPathFit.spacing),
];

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

ui.Paragraph label(String text, double size, Color color, {FontWeight weight = FontWeight.w600}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Deva', fontSize: size, fontWeight: weight))
    ..pushStyle(ui.TextStyle(color: color, fontFamily: 'Deva', fontSize: size, fontWeight: weight))
    ..addText(text);
  return b.build()..layout(const ui.ParagraphConstraints(width: 2000));
}

/// Where the placed text's ink reaches, traced round each cluster's ink box.
Rect placedBounds(TextOnPathPlacement p) {
  Rect? box;
  for (var i = 0; i < p.text.units.length; i++) {
    final r = p.text.units[i].ink;
    if (r.isEmpty) continue;
    for (var k = 0; k <= 6; k++) {
      final f = k / 6;
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

Future<void> save(ui.Picture picture, Size size, String path) async {
  final image = await picture.toImage((size.width * scale).round(), (size.height * scale).round());
  File(path).writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final s in samples) {
      await loadFont(s.$2, s.$3);
    }
  });

  test('gallery', () async {
    const card = Size(640, 300), fontSize = 40.0;
    for (final (name, family, _, text, meaning, _) in samples) {
      final shaped = await ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: fontSize, color: ink));
      final atlas = await shaped.drawAtlas(2 * scale);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(scale)
        ..drawRect(Offset.zero & card, Paint()..color = paper);
      final title = label(name, 18, ink);
      canvas.drawParagraph(title, const Offset(20, 14));
      final note = label(meaning, 13, muted, weight: FontWeight.w400);
      canvas.drawParagraph(note, Offset(30 + title.maxIntrinsicWidth, 19));
      // An arc on the left, an S-curve on the right, each centred in its half.
      final arcCurve = PathCurve.arc(Offset.zero, math.max(2.6 * fontSize, shaped.width / 2.4));
      final w = shaped.width * 1.1;
      final sCurve = PathCurve.fromPath(
        Path()
          ..moveTo(-w / 2, 0)
          ..cubicTo(-w / 6, -0.32 * w, w / 6, 0.32 * w, w / 2, 0),
      );
      for (final (k, curve) in [arcCurve, sCurve].indexed) {
        final placement = TextOnPathPlacement(shaped, curve);
        final box = placedBounds(placement);
        final area = Rect.fromLTWH(k * card.width / 2 + 10, 50, card.width / 2 - 20, card.height - 64);
        final fit = math.min(1.0, math.min(area.width / box.width, area.height / box.height));
        canvas
          ..save()
          ..translate(area.center.dx, area.center.dy)
          ..scale(fit)
          ..translate(-box.center.dx, -box.center.dy)
          ..drawPath(
            curve.toPath(),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1 / fit
              ..color = const Color(0x22000000),
          );
        placement.paint(canvas, atlas: atlas);
        canvas.restore();
      }
      await save(recorder.endRecording(), card, 'doc/images/gallery_${name.toLowerCase().replaceAll(' ', '_')}.png');
      atlas.dispose();
      shaped.dispose();
    }
  });

  test('seals', () async {
    const cell = 300.0, columns = 3, labelHeight = 36.0;
    final rows = (samples.length / columns).ceil();
    final size = Size(cell * columns, (cell + labelHeight) * rows);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..drawRect(Offset.zero & size, Paint()..color = paper);
    for (final (i, (name, family, _, text, _, fit)) in samples.indexed) {
      final origin = Offset((i % columns) * cell, (i ~/ columns) * (cell + labelHeight));
      final centre = origin + const Offset(cell / 2, cell / 2);
      final phrase = '$text  $text  ';
      // A size that takes the phrase about 86% of the way round a ring inside the cell.
      final probe = await ShapedText.layout(phrase, TextStyle(fontFamily: family, fontSize: 100), scale: 1);
      var up = 0.0, down = 0.0;
      for (final u in probe.units) {
        up = math.max(up, (probe.baseline - u.ink.top) / 100);
        down = math.max(down, (u.ink.bottom - probe.baseline) / 100);
      }
      final perPixel = probe.width / 100;
      probe.dispose();
      final fontSize = 0.86 * math.pi * (cell - 30) / (perPixel + 0.86 * 2 * math.pi * (up + 0.15));
      final shaped = await ShapedText.layout(
        phrase,
        TextStyle(fontFamily: family, fontSize: fontSize, color: sealRed),
        scale: 2 * scale,
      );
      final gap = 0.15 * fontSize;
      final r = (cell - 30) / 2 - up * fontSize - gap;
      final ring = PathCurve.arc(centre, r);
      final rings = Paint()
        ..style = PaintingStyle.stroke
        ..color = sealRed;
      canvas
        ..drawCircle(centre, r + up * fontSize + gap, rings..strokeWidth = 2.4)
        ..drawCircle(centre, r + up * fontSize + gap + 4, rings..strokeWidth = 0.8)
        ..drawCircle(centre, r - down * fontSize - gap, rings..strokeWidth = 1.2);
      TextOnPathPlacement(shaped, ring, fit: fit, fitLength: ring.length - fontSize).paint(canvas);
      final l = label('$name · ${fit == TextOnPathFit.spacing ? 'word spacing' : fit.name}', 14, ink);
      canvas.drawParagraph(l, origin + Offset((cell - l.maxIntrinsicWidth) / 2, cell - 4));
      shaped.dispose();
    }
    await save(recorder.endRecording(), size, 'doc/images/seals.png');
  });
}
