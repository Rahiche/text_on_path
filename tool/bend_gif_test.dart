// Draws the frames of doc/images/bend.gif: Hindi and Urdu on a circle that bends from nearly flat to tight and back,
// rigid placement cluster by cluster beside joined placement.
//
// Run from the package's folder, then join the frames with ffmpeg:
//   flutter test tool/bend_gif_test.dart --dart-define=FRAMES=/tmp/bend
//   ffmpeg -y -framerate 15 -i /tmp/bend/%03d.png -vf "split[a][b];[a]palettegen=max_colors=48[p];[b][p]paletteuse=dither=none" -loop 0 doc/images/bend.gif
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const frames = String.fromEnvironment('FRAMES', defaultValue: '/tmp/bend');
const ink = Color(0xff1d1a16);
const fontSize = 34.0;
const count = 60;

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

ui.Paragraph label(String text, double size, Color color) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Deva', fontSize: size, fontWeight: FontWeight.w600))
    ..pushStyle(ui.TextStyle(color: color, fontFamily: 'Deva', fontSize: size, fontWeight: FontWeight.w600))
    ..addText(text);
  return b.build()..layout(const ui.ParagraphConstraints(width: 1000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frames', () async {
    Directory(frames).createSync(recursive: true);
    await loadFont('Deva', 'NotoSansDevanagari.ttf');
    await loadFont('Nastaliq', 'NotoNastaliqUrdu.ttf');
    final rows = [
      await ShapedText.layout(
          'शिरोरेखा जुड़ी रहती', const TextStyle(fontFamily: 'Deva', fontSize: fontSize, color: ink)),
      await ShapedText.layout('بہت شکریہ', const TextStyle(fontFamily: 'Nastaliq', fontSize: fontSize, color: ink)),
    ];
    const width = 960.0, height = 500.0, head = 44.0;
    const columns = [
      (TextOnPathMode.rigid, 'Rigid, cluster by cluster', Color(0xffa1432c)),
      (TextOnPathMode.joined, 'text_on_path', Color(0xff0f6e5c)),
    ];
    for (var f = 0; f < count; f++) {
      // Out to a tight bend and back, easing at both ends.
      final t = 0.5 - 0.5 * math.cos(2 * math.pi * f / count);
      final radius = fontSize / (1 / 30 + t * (1 / 2.3 - 1 / 30));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xfffbf8f2));
      for (final (c, (_, title, colour)) in columns.indexed) {
        final l = label(title, 17, colour);
        canvas.drawParagraph(l, Offset(c * width / 2 + (width / 2 - l.maxIntrinsicWidth) / 2, 12));
      }
      canvas.drawRect(
          Rect.fromLTWH(width / 2 - 0.5, head, 1, height - head - 10), Paint()..color = const Color(0xffe4ddd1));
      for (final (r, shaped) in rows.indexed) {
        for (final (c, (mode, _, _)) in columns.indexed) {
          // The top of the circle stays put as it bends.
          final top = Offset(c * width / 2 + width / 4, head + 70 + r * 210.0);
          final curve = PathCurve.arc(top + Offset(0, radius), radius);
          canvas
            ..save()
            ..clipRect(Rect.fromLTWH(c * width / 2, head + r * 210.0, width / 2, 210));
          canvas.drawPath(
            curve.toPath(),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0x22000000),
          );
          TextOnPathPlacement(shaped, curve, mode: mode).paint(canvas);
          canvas.restore();
        }
      }
      final image = await recorder.endRecording().toImage(width.round(), height.round());
      File('$frames/${f.toString().padLeft(3, '0')}.png')
          .writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    }
    for (final s in rows) {
      s.dispose();
    }
  });
}
