// Draws the frames of doc/images/bend.gif: Hindi and Urdu on a circle that bends from nearly flat to tight and back,
// rigid placement cluster by cluster beside text_on_path, each with a loupe on the join rigid placement opens widest.
//
// Run from the package's folder, then join the frames with ffmpeg:
//   flutter test tool/bend_gif_test.dart --dart-define=FRAMES=/tmp/bend
//   ffmpeg -y -framerate 15 -i /tmp/bend/%03d.png -vf "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" -loop 0 doc/images/bend.gif
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const frames = String.fromEnvironment('FRAMES', defaultValue: '/tmp/bend');
const ink = Color(0xff1d1a16);
const paper = Color(0xfffbf8f2);
const rigidColour = Color(0xffa1432c);
const joinedColour = Color(0xff0f6e5c);
const fontSize = 40.0;
const count = 72;

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

/// The join rigid placement opens widest on [curve], and the row through its middle.
(UnitPair, double) worstJoin(ShapedText shaped, PathCurve curve) {
  final rigid = TextOnPathPlacement(shaped, curve, mode: TextOnPathMode.rigid);
  late UnitPair worst;
  var row = 0.0, widest = -1.0;
  for (final p in shaped.neighbours) {
    if (!p.joins) continue;
    for (final (y0, y1) in p.crossing) {
      for (final y in [y0 + 0.5, (y0 + y1) / 2, y1 - 0.5]) {
        final d = (rigid.map(p.left, p.x, y) - rigid.map(p.right, p.x, y)).distance;
        if (d > widest) {
          widest = d;
          worst = p;
          row = (y0 + y1) / 2;
        }
      }
    }
  }
  return (worst, row);
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
    const width = 960.0, rowHeight = 250.0, head = 48.0, foot = 34.0;
    const height = head + 2 * rowHeight + foot;
    const columns = [
      (TextOnPathMode.rigid, 'Turned cluster by cluster', rigidColour),
      (TextOnPathMode.joined, 'text_on_path', joinedColour),
    ];
    const tightest = 2.2, flattest = 30.0;
    // The loupes look at the join rigid placement opens widest at the tightest bend, the same one all the way.
    final joins = [
      for (final s in rows) worstJoin(s, PathCurve.arc(Offset.zero, tightest * fontSize)),
    ];
    // An atlas for the view and a denser one for the loupes, each two texels to a pixel it's shown at.
    const zoom = 3.2;
    final atlases = [for (final s in rows) await s.drawAtlas(2)];
    final dense = [for (final s in rows) await s.drawAtlas(2 * zoom)];

    for (var f = 0; f < count; f++) {
      // Out to a tight bend and back, easing at both ends.
      final t = 0.5 - 0.5 * math.cos(2 * math.pi * f / count);
      final bend = 1 / flattest + t * (1 / tightest - 1 / flattest);
      final radius = fontSize / bend;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = paper);
      for (final (c, (_, title, colour)) in columns.indexed) {
        final l = label(title, 19, colour);
        canvas.drawParagraph(l, Offset(c * width / 2 + (width / 2 - l.maxIntrinsicWidth) / 2, 12));
      }
      canvas.drawRect(Rect.fromLTWH(width / 2 - 0.5, head, 1, 2 * rowHeight), Paint()..color = const Color(0xffe4ddd1));
      for (final (r, shaped) in rows.indexed) {
        for (final (c, (mode, _, colour)) in columns.indexed) {
          final panel = Rect.fromLTWH(c * width / 2, head + r * rowHeight, width / 2, rowHeight);
          // The top of the circle stays put as it bends.
          final top = Offset(panel.left + panel.width * 0.4, panel.top + 92);
          final curve = PathCurve.arc(top + Offset(0, radius), radius);
          final placement = TextOnPathPlacement(shaped, curve, mode: mode);
          canvas
            ..save()
            ..clipRect(panel);
          void scene(TextAtlas atlas) {
            canvas.drawPath(
              curve.toPath(),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = const Color(0x26000000),
            );
            placement.paint(canvas, atlas: atlas);
          }

          scene(atlases[r]);
          // The loupe: the join, magnified, in the panel's corner.
          final (pair, row) = joins[r];
          final spot = (placement.map(pair.left, pair.x, row) + placement.map(pair.right, pair.x, row)) / 2;
          const reach = 62.0;
          final centre = Offset(panel.right - reach - 14, panel.bottom - reach - 12);
          final edge = Paint()
            ..style = PaintingStyle.stroke
            ..color = colour;
          canvas.drawCircle(spot, reach / zoom, edge..strokeWidth = 1.4);
          final towards = centre - spot;
          final unit = towards / towards.distance;
          canvas.drawLine(spot + unit * (reach / zoom), centre - unit * reach, edge..strokeWidth = 1);
          canvas
            ..save()
            ..clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: reach)))
            ..drawPaint(Paint()..color = const Color(0xffffffff))
            ..translate(centre.dx, centre.dy)
            ..scale(zoom)
            ..translate(-spot.dx, -spot.dy);
          scene(dense[r]);
          canvas.restore();
          canvas.drawCircle(centre, reach, edge..strokeWidth = 2);
          canvas.restore();
        }
      }
      // How far it's bent.
      final bar = Rect.fromLTWH(24, height - 22, width - 48, 4);
      canvas
        ..drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = const Color(0xffe4ddd1))
        ..drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(bar.left, bar.top, bar.width * t, bar.height), const Radius.circular(2)),
          Paint()..color = const Color(0xff7a7268),
        );
      final b = label('bend', 13, const Color(0xff7a7268), weight: FontWeight.w400);
      canvas.drawParagraph(b, Offset(24, height - 42));
      final image = await recorder.endRecording().toImage(width.round(), height.round());
      File('$frames/${f.toString().padLeft(3, '0')}.png')
          .writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    }
    for (final a in [...atlases, ...dense]) {
      a.dispose();
    }
    for (final s in rows) {
      s.dispose();
    }
  });
}
