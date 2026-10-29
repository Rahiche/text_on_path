// Shows selection on curved text: for Arabic, Hindi and a Latin script hand, a mouse drag's highlight and a long
// press's word with its handles, written to doc/images/selection_<script>.png.
//
// Run from the package's folder:
//   flutter test tool/selection_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// (name, family, text, a word in it)
const samples = [
  ('arabic', 'Naskh', 'الحروف تبقى متصلة', 'تبقى'),
  ('hindi', 'Deva', 'शिरोरेखा जुड़ी रहती', 'जुड़ी'),
  ('latin_script', 'Dancing', 'Handwriting stays joined', 'stays'),
];

void main() {
  setUpAll(() async {
    await loadFont('Naskh', 'NotoNaskhArabic.ttf');
    await loadFont('Deva', 'NotoSansDevanagari.ttf');
    await loadFont('Dancing', 'DancingScript.ttf');
  });

  const size = Size(520, 330);
  final curve = PathCurve.arc(const Offset(260, 300), 170);

  for (final (name, family, text, word) in samples) {
    testWidgets(name, (tester) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final style = TextStyle(fontFamily: family, fontSize: 40, color: const Color(0xff1d1a16));
      final shots = <ui.Image>[];
      for (final touch in [false, true]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: const Color(0xfffbf8f2),
                body: SelectionArea(
                  contextMenuBuilder: (context, state) => const SizedBox.shrink(),
                  child: TextOnPath(text, curve: curve, style: style),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pump();
        }
        final shaped = (await tester.runAsync(() => ShapedText.layout(text, style)))!;
        final p = TextOnPathPlacement(shaped, curve);
        Offset at(int codeUnit, {bool before = false}) {
          final i = shaped.units.indexWhere((u) => u.range.start <= codeUnit && codeUnit < u.range.end);
          final u = shaped.units[i];
          final rtl = shaped.textDirection == TextDirection.rtl;
          final x = before ? (rtl ? u.box.right + 2 : u.box.left - 2) : u.anchor;
          return p.map(i, x, shaped.baseline - 0.3 * shaped.fontSize);
        }

        final middle = at(text.indexOf(word) + word.length ~/ 2);
        if (touch) {
          await tester.longPressAt(middle);
        } else {
          final from = at(0, before: true);
          final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
          await tester.pump();
          for (var k = 1; k <= 10; k++) {
            await mouse.moveTo(Offset.lerp(from, middle, k / 10)!);
            await tester.pump();
          }
          await mouse.up();
        }
        await tester.pumpAndSettle();
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        shots.add((await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!);
        shaped.dispose();
        await tester.pump(const Duration(seconds: 1));
      }
      // Side by side: the drag, then the long press.
      final sheet = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final (k, shot) in shots.indexed) {
          canvas.drawImage(shot, Offset(k * (shot.width + 16.0), 0), Paint());
        }
        canvas.drawRect(
          Rect.fromLTWH(shots.first.width.toDouble(), 0, 16, shots.first.height.toDouble()),
          Paint()..color = const Color(0xffe4ddd1),
        );
        final image = await recorder.endRecording().toImage(2 * shots.first.width + 16, shots.first.height);
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      }))!;
      File('doc/images/selection_$name.png').writeAsBytesSync(sheet);
    });
  }
}
