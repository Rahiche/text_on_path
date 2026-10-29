// Draws the frames of doc/images/seal.gif: a phrase fitted round a seal as it's stretched to fill the ring, turned
// cluster by cluster beside text_on_path. Turned whole, the letters part and their joins open; text_on_path draws the
// joins out instead, by kashida in Arabic and by tracking along the headline in Hindi.
//
// Run from the package's folder, then join the frames with ffmpeg:
//   flutter test tool/seal_gif_test.dart --dart-define=FRAMES=/tmp/seal
//   ffmpeg -y -framerate 15 -i /tmp/seal/%03d.png -vf "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" -loop 0 doc/images/seal.gif
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const frames = String.fromEnvironment('FRAMES', defaultValue: '/tmp/seal');
const ink = Color(0xff1d1a16);
const paper = Color(0xfffbf8f2);
const muted = Color(0xff7a7268);
const line = Color(0xffe4ddd1);
const sealRed = Color(0xff9c1d15);
const rigidColour = Color(0xffa1432c);
const joinedColour = Color(0xff0f6e5c);

/// (name, family, font file, text, fit, what the fit draws out)
const scenes = [
  ('Arabic', 'Naskh', 'NotoNaskhArabic.ttf', 'الحروف تبقى متصلة', TextOnPathFit.kashida, 'kashida'),
  ('Hindi', 'Deva', 'NotoSansDevanagari.ttf', 'शिरोरेखा जुड़ी रहती है', TextOnPathFit.tracking, 'tracking'),
];

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

ui.Paragraph label(String text, double size, Color color, {FontWeight weight = FontWeight.w600}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Deva', fontSize: size, fontWeight: weight))
    ..pushStyle(ui.TextStyle(color: color, fontFamily: 'Deva', fontSize: size, fontWeight: weight))
    ..addText(text);
  return b.build()..layout(const ui.ParagraphConstraints(width: 1000));
}

/// How many of [placement]'s joins visibly open or overlap: their two sides, as drawn, more than half a pixel apart.
int openJoins(TextOnPathPlacement placement) {
  var open = 0;
  for (final p in placement.text.neighbours) {
    if (!p.joins) continue;
    var worst = 0.0;
    for (final (y0, y1) in p.crossing) {
      for (final y in [y0 + 0.5, (y0 + y1) / 2, y1 - 0.5]) {
        for (final (a, b) in placement.joinCopies(p, y)) {
          worst = math.max(worst, (b - a).distance);
        }
      }
    }
    if (worst > 0.5) open++;
  }
  return open;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frames', () async {
    Directory(frames).createSync(recursive: true);
    for (final s in scenes) {
      await loadFont(s.$2, s.$3);
    }
    const width = 720.0, height = 450.0, head = 42.0;
    const columns = [
      (TextOnPathMode.rigid, 'Turned cluster by cluster', rigidColour),
      (TextOnPathMode.joined, 'text_on_path', joinedColour),
    ];
    // Each seal's outer ring, and how far round it the phrase goes before it's stretched.
    const outer = 150.0, natural = 0.7;
    // Natural length, then stretched to fill the ring, held, and let go: the frames' stretch, 0 to 1.
    final stretches = [
      for (var k = 0; k < 5; k++) 0.0,
      for (var k = 1; k <= 24; k++) Curves.easeInOut.transform(k / 24),
      for (var k = 0; k < 12; k++) 1.0,
      for (var k = 1; k <= 10; k++) Curves.easeInOut.transform(1 - k / 10),
    ];
    var frame = 0;
    for (final (name, family, _, text, fit, how) in scenes) {
      // A size that takes the phrase [natural] of the way round a ring inside the seal, its ink's reach above the
      // baseline inside the outer ring.
      final probe = await ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: 100), scale: 1);
      var up = 0.0, down = 0.0;
      for (final u in probe.units) {
        up = math.max(up, (probe.baseline - u.ink.top) / 100);
        down = math.max(down, (u.ink.bottom - probe.baseline) / 100);
      }
      final perPixel = probe.width / 100;
      probe.dispose();
      final fontSize = natural * math.pi * 2 * outer / (perPixel + natural * 2 * math.pi * (up + 0.15));
      final shaped = await ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: fontSize, color: sealRed));
      final gap = 0.15 * fontSize;
      final r = outer - up * fontSize - gap;
      final centres = [for (var c = 0; c < columns.length; c++) Offset(c * width / 2 + width / 4, head + outer + 14)];
      final rings = [for (final centre in centres) PathCurve.arc(centre, r)];
      // Stretched, the phrase fills the ring but for an em at the bottom.
      final full = rings.first.length - fontSize;
      final naturals = [
        for (final (c, (mode, _, _)) in columns.indexed) TextOnPathPlacement(shaped, rings[c], mode: mode).length,
      ];

      for (final t in stretches) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = paper);
        canvas.drawRect(Rect.fromLTWH(width / 2 - 0.5, head, 1, 2 * outer + 50), Paint()..color = line);
        var fitLength = 0.0;
        for (final (c, (mode, title, colour)) in columns.indexed) {
          final l = label(title, 18, colour);
          canvas.drawParagraph(l, Offset(c * width / 2 + (width / 2 - l.maxIntrinsicWidth) / 2, 10));
          final ring = rings[c], centre = centres[c];
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..color = sealRed;
          canvas
            ..drawCircle(centre, outer, paint..strokeWidth = 2.4)
            ..drawCircle(centre, outer + 4, paint..strokeWidth = 0.8)
            ..drawCircle(centre, r - down * fontSize - gap, paint..strokeWidth = 1.2);
          // Without a fitLength, a fit fills the whole ring: so from its natural length, always given.
          fitLength = naturals[c] + t * (full - naturals[c]);
          final placement = TextOnPathPlacement(shaped, ring, mode: mode, fit: fit, fitLength: fitLength);
          placement.paint(canvas);
          final joins = shaped.neighbours.where((p) => p.joins).length;
          final open = openJoins(placement);
          final count = label('$open of $joins joins open', 15, open > 0 ? rigidColour : joinedColour);
          canvas.drawParagraph(
            count,
            Offset(c * width / 2 + (width / 2 - count.maxIntrinsicWidth) / 2, centre.dy + outer + 12),
          );
        }
        // What's stretched, and by how much.
        final caption = label('$name, stretched by $how', 15, ink);
        canvas.drawParagraph(caption, const Offset(24, height - 52));
        final longer = (100 * (fitLength / naturals.last - 1)).round();
        final amount = label('+$longer%', 14, muted, weight: FontWeight.w400);
        canvas.drawParagraph(amount, Offset(width - 24 - amount.maxIntrinsicWidth, height - 51));
        final bar = Rect.fromLTWH(24, height - 22, width - 48, 4);
        canvas
          ..drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = line)
          ..drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(bar.left, bar.top, bar.width * t, bar.height), const Radius.circular(2)),
            Paint()..color = muted,
          );
        final image = await recorder.endRecording().toImage(width.round(), height.round());
        File('$frames/${(frame++).toString().padLeft(3, '0')}.png')
            .writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        image.dispose();
      }
      shaped.dispose();
    }
  });
}
