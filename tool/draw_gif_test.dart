// Draws the frames of doc/images/draw.gif: a curve drawn by hand, with the text riding along it just behind the pen,
// its joins closed through every bend; then the text settles in the curve's middle. Arabic, then a Latin script hand.
//
// Run from the package's folder, then join the frames with ffmpeg:
//   flutter test tool/draw_gif_test.dart --dart-define=FRAMES=/tmp/draw
//   ffmpeg -y -framerate 15 -i /tmp/draw/%03d.png -vf "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" -loop 0 doc/images/draw.gif
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const frames = String.fromEnvironment('FRAMES', defaultValue: '/tmp/draw');
const ink = Color(0xff1d1a16);
const paper = Color(0xfffbf8f2);
const muted = Color(0xff7a7268);
const pencil = Color(0xffcfc6b8);
const joinedColour = Color(0xff0f6e5c);

/// (name, family, font file, text, the stroke's seed)
const scenes = [
  ('Arabic', 'Naskh', 'NotoNaskhArabic.ttf', 'الحروف تبقى متصلة', 3),
  ('Latin script', 'Dancing', 'DancingScript.ttf', 'Handwriting stays joined', 8),
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

/// A wave drawn by hand from off the left edge to near the right one: uneven swells, a little wobble, smoothed as the
/// example app smooths a stroke.
Path freehand(int seed, double middle) {
  final random = math.Random(seed);
  final points = <Offset>[];
  for (var x = -70.0; x <= 690; x += 26) {
    final swell = 0.85 + 0.2 * math.sin(x / 210 + seed);
    final y = middle + 45 * swell * math.sin(2 * math.pi * x / 420 + seed) + 1.6 * (random.nextDouble() - 0.5);
    points.add(Offset(x + 6 * (random.nextDouble() - 0.5), y));
  }
  // A Catmull-Rom spline through the points, as cubic Béziers.
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i + 1 < points.length; i++) {
    final p0 = points[math.max(0, i - 1)], p1 = points[i], p2 = points[i + 1];
    final p3 = points[math.min(points.length - 1, i + 2)];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frames', () async {
    Directory(frames).createSync(recursive: true);
    for (final s in scenes) {
      await loadFont(s.$2, s.$3);
    }
    // The labels' font.
    await loadFont('Deva', 'NotoSansDevanagari.ttf');
    const width = 720.0, height = 300.0;
    // Frames for the pen to draw the stroke, for the text to settle, and to hold.
    const drawing = 40, settling = 12, holding = 12;
    // How far the text's front end stays behind the pen.
    const lead = 14.0;
    var frame = 0;
    for (final (name, family, _, text, seed) in scenes) {
      final stroke = freehand(seed, height * 0.58);
      final metric = stroke.computeMetrics().first;
      final curve = PathCurve.fromPath(stroke);
      // A size that takes the text a little under half the stroke.
      final probe = await ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: 100), scale: 1);
      final fontSize = math.min(48.0, 0.46 * curve.length / (probe.width / 100));
      probe.dispose();
      final shaped = await ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: fontSize, color: ink));
      final half = shaped.width / 2;

      // Where the pen is along the stroke, and where the text's middle is, frame by frame.
      final steps = <(double?, double)>[
        for (var k = 0; k <= drawing; k++)
          () {
            final pen = curve.length * Curves.easeInOutSine.transform(k / drawing);
            return (pen, pen - lead - half);
          }(),
        for (var k = 1; k <= settling; k++)
          (
            null,
            ui.lerpDouble(curve.length - lead - half, curve.length / 2, Curves.easeInOut.transform(k / settling))!
          ),
        for (var k = 0; k < holding; k++) (null, curve.length / 2),
      ];
      for (final (pen, middle) in steps) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = paper);
        canvas.drawParagraph(label(name, 15, muted), const Offset(24, 16));
        canvas.drawPath(
          metric.extractPath(0, pen ?? metric.length),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = pencil,
        );
        TextOnPathPlacement(shaped, curve, position: middle / curve.length).paint(canvas);
        if (pen != null) {
          final tip = curve.pointAt(pen);
          canvas
            ..drawCircle(tip, 12, Paint()..color = joinedColour.withValues(alpha: 0.14))
            ..drawCircle(tip, 5, Paint()..color = joinedColour);
        }
        final image = await recorder.endRecording().toImage(width.round(), height.round());
        File('$frames/${(frame++).toString().padLeft(3, '0')}.png')
            .writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        image.dispose();
      }
      shaped.dispose();
    }
  });
}
