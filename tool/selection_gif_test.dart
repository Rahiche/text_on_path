// Draws the frames of doc/images/selection.gif: curved text selected inside a SelectionArea. A mouse drags across
// Arabic on an arc, right to left as it reads, then double-clicks a word of Hindi; the highlight bends with the curve,
// and what's selected shows underneath. The widgets, the gestures and the selection are the real ones; only the
// pointer and its clicks are drawn over them.
//
// Run from the package's folder, then join the frames with ffmpeg:
//   flutter test tool/selection_gif_test.dart --dart-define=FRAMES=/tmp/selection
//   ffmpeg -y -framerate 15 -i /tmp/selection/%03d.png -vf "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" -loop 0 doc/images/selection.gif
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

const frames = String.fromEnvironment('FRAMES', defaultValue: '/tmp/selection');
const ink = Color(0xff1d1a16);
const paper = Color(0xfffbf8f2);
const muted = Color(0xff7a7268);
const line = Color(0xffe4ddd1);
const joinedColour = Color(0xff0f6e5c);
const size = Size(720, 360);
const fontSize = 34.0;

/// (what to do, family, text, the word aimed at)
const samples = [
  ('Drag across Arabic, right to left', 'Naskh', 'الحروف تبقى متصلة', 'تبقى'),
  ('Double-click a word of Hindi', 'Deva', 'शिरोरेखा जुड़ी रहती', 'जुड़ी'),
];

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// The mouse pointer drawn over the scene, and a ring for each click, fading as it grows.
class Pointer extends ChangeNotifier {
  Offset at = Offset.zero;
  final clicks = <double>[];

  void moveTo(Offset to) {
    at = to;
    notifyListeners();
  }

  void click() {
    clicks.add(0);
    notifyListeners();
  }

  /// A frame on: each ring a quarter of the way further.
  void age() {
    for (var i = 0; i < clicks.length; i++) {
      clicks[i] += 0.25;
    }
    clicks.removeWhere((a) => a >= 1);
    notifyListeners();
  }
}

class PointerPainter extends CustomPainter {
  PointerPainter(this.pointer) : super(repaint: pointer);

  final Pointer pointer;

  @override
  void paint(Canvas canvas, Size size) {
    for (final age in pointer.clicks) {
      canvas.drawCircle(
        pointer.at,
        5 + 16 * age,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 + 2.5 * (1 - age)
          ..color = joinedColour.withValues(alpha: 1 - age),
      );
    }
    // An arrow, its tip on the point.
    final arrow = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 17)
      ..lineTo(4.3, 13)
      ..lineTo(7.3, 19.6)
      ..lineTo(10, 18.5)
      ..lineTo(7, 12)
      ..lineTo(12.2, 12)
      ..close();
    canvas
      ..save()
      ..translate(pointer.at.dx, pointer.at.dy)
      ..drawPath(arrow, Paint()..color = const Color(0xffffffff))
      ..drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xff000000),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(PointerPainter old) => old.pointer != pointer;
}

class GuidePainter extends CustomPainter {
  GuidePainter(this.curve);

  final PathCurve curve;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
        curve.toPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x22000000),
      );

  @override
  bool shouldRepaint(GuidePainter old) => old.curve != curve;
}

void main() {
  setUpAll(() async {
    await loadFont('Naskh', 'NotoNaskhArabic.ttf');
    await loadFont('Deva', 'NotoSansDevanagari.ttf');
  });

  testWidgets('frames', (tester) async {
    Directory(frames).createSync(recursive: true);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Each sample's text, shaped as the widget shapes it, on an arc that takes it about 100° round.
    final shaped = <ShapedText>[];
    final curves = <PathCurve>[];
    for (final (_, family, text, _) in samples) {
      final s = (await tester.runAsync(
        () => ShapedText.layout(text, TextStyle(fontFamily: family, fontSize: fontSize, color: ink)),
      ))!;
      addTearDown(s.dispose);
      final r = (s.width / 1.75).clamp(140.0, 200.0);
      shaped.add(s);
      curves.add(PathCurve.arc(Offset(180, 30 + 1.2 * fontSize + r), r));
    }

    final pointer = Pointer();
    final selected = ValueNotifier('');
    final boundary = GlobalKey();
    final keys = [for (final _ in samples) GlobalKey()];
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Deva', fontFamilyFallback: const ['Naskh']),
          home: Scaffold(
            backgroundColor: paper,
            body: Stack(
              children: [
                Positioned(left: 359.5, top: 14, width: 1, height: 262, child: const ColoredBox(color: line)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectionArea(
                      contextMenuBuilder: (context, state) => const SizedBox.shrink(),
                      onSelectionChanged: (content) => selected.value = content?.plainText ?? '',
                      child: DefaultSelectionStyle(
                        selectionColor: joinedColour.withValues(alpha: 0.3),
                        child: Row(
                          children: [
                            for (final (i, (title, family, text, _)) in samples.indexed)
                              SizedBox(
                                width: 360,
                                height: 286,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                                      child: Text(
                                        title,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: muted),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 360,
                                      height: 250,
                                      child: ClipRect(
                                        child: Stack(
                                          children: [
                                            Positioned.fill(child: CustomPaint(painter: GuidePainter(curves[i]))),
                                            Positioned.fill(
                                              child: TextOnPath(
                                                text,
                                                key: keys[i],
                                                curve: curves[i],
                                                style: TextStyle(fontFamily: family, fontSize: fontSize, color: ink),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      width: size.width - 44,
                      decoration: BoxDecoration(
                        color: const Color(0xffffffff),
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ValueListenableBuilder(
                        valueListenable: selected,
                        builder: (context, text, _) => Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Selected   ', style: TextStyle(color: muted)),
                              TextSpan(
                                text: text,
                                style: const TextStyle(color: ink, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: PointerPainter(pointer)))),
              ],
            ),
          ),
        ),
      ),
    );
    // Let the widgets shape their text and draw their atlases.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }

    var frame = 0;
    Future<void> shot() async {
      await tester.pump(const Duration(milliseconds: 66));
      final box = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await tester.runAsync(() async {
        final image = await box.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        image.dispose();
        return bytes;
      });
      File('$frames/${(frame++).toString().padLeft(3, '0')}.png').writeAsBytesSync(png!);
      pointer.age();
    }

    /// The point on screen of sample [i]'s flat point ([x], [y]), as the widget draws it.
    Offset at(int i, double x, double y) {
      final placement = TextOnPathPlacement(shaped[i], curves[i]);
      return tester.getTopLeft(find.byKey(keys[i])) + placement.bandPoint(x, y).$1;
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    Future<void> glide(Offset to, int count) async {
      final from = pointer.at;
      for (var k = 1; k <= count; k++) {
        final p = Offset.lerp(from, to, Curves.easeInOut.transform(k / count))!;
        await mouse.moveTo(p);
        pointer.moveTo(p);
        await shot();
      }
    }

    // At rest, between the two.
    const rest = Offset(330, 236);
    await mouse.addPointer(location: rest);
    pointer.moveTo(rest);
    for (var k = 0; k < 4; k++) {
      await shot();
    }

    // Arabic: from just past its first letter, at the right, along the arc to the end of the second word.
    final arabic = shaped[0], middle = arabic.baseline - 0.35 * fontSize;
    final word = arabic.text.indexOf(samples[0].$4);
    final wordBox = arabic.paragraph.getBoxesForRange(word, word + samples[0].$4.length).first;
    final from = arabic.width + 6, to = wordBox.left - 4;
    await glide(at(0, from, middle), 8);
    await mouse.down(pointer.at);
    pointer.click();
    await shot();
    await shot();
    const steps = 24;
    for (var k = 1; k <= steps; k++) {
      final p = at(0, ui.lerpDouble(from, to, k / steps)!, middle);
      await mouse.moveTo(p);
      pointer.moveTo(p);
      await shot();
    }
    await mouse.up();
    for (var k = 0; k < 12; k++) {
      await shot();
    }

    // Hindi: a double-click on the middle of a word.
    final hindi = shaped[1];
    final target = hindi.text.indexOf(samples[1].$4);
    final targetBox = hindi.paragraph.getBoxesForRange(target, target + samples[1].$4.length).first;
    await glide(at(1, (targetBox.left + targetBox.right) / 2, hindi.baseline - 0.35 * fontSize), 9);
    for (var k = 0; k < 2; k++) {
      await mouse.down(pointer.at);
      pointer.click();
      await shot();
      await mouse.up();
      await shot();
    }
    for (var k = 0; k < 14; k++) {
      await shot();
    }

    // A click on nothing clears it, and back to rest.
    await glide(const Offset(560, 262), 7);
    await mouse.down(pointer.at);
    pointer.click();
    await shot();
    await mouse.up();
    for (var k = 0; k < 4; k++) {
      await shot();
    }
    await glide(rest, 7);
    await tester.pump(const Duration(seconds: 1));
    debugPrint('frames: $frame; selected at the end: "${selected.value}"');
  });
}
