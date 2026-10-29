import 'dart:io';

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

/// (family, text, a word in it)
const samples = [
  ('Naskh', 'الحروف تبقى متصلة', 'تبقى'),
  ('Deva', 'शिरोरेखा जुड़ी रहती', 'जुड़ी'),
  ('Dancing', 'Handwriting stays joined', 'stays'),
];

void main() {
  setUpAll(() async {
    await loadFont('Naskh', 'NotoNaskhArabic.ttf');
    await loadFont('Deva', 'NotoSansDevanagari.ttf');
    await loadFont('Dancing', 'DancingScript.ttf');
  });

  final curve = PathCurve.arc(const Offset(260, 280), 150);

  /// The text on a circle in a [SelectionArea], shaped and drawn; and the same text placed the same way, to aim with.
  Future<(TextOnPathPlacement, ValueNotifier<SelectedContent?>)> show(
    WidgetTester tester,
    String family,
    String text,
  ) async {
    final style = TextStyle(fontFamily: family, fontSize: 40, color: Colors.black);
    final selected = ValueNotifier<SelectedContent?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) => selected.value = content,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 520, height: 480, child: TextOnPath(text, curve: curve, style: style)),
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
    addTearDown(shaped.dispose);
    // Let the gestures' timers (a double tap's, a long press's) run out before the test ends.
    addTearDown(() => tester.pump(const Duration(seconds: 1)));
    return (TextOnPathPlacement(shaped, curve), selected);
  }

  /// Where, on screen, the middle of the cluster holding [codeUnit] is drawn; or, [before] it, just outside its
  /// edge on the side the text is read from.
  Offset at(WidgetTester tester, TextOnPathPlacement p, int codeUnit, {bool before = false}) {
    final text = p.text;
    final i = text.units.indexWhere((u) => u.range.start <= codeUnit && codeUnit < u.range.end);
    final u = text.units[i];
    final rtl = text.textDirection == TextDirection.rtl;
    final x = before ? (rtl ? u.box.right + 2 : u.box.left - 2) : u.anchor;
    final local = p.map(i, x, text.baseline - 0.3 * text.fontSize);
    return tester.getTopLeft(find.byType(TextOnPath)) + local;
  }

  for (final (family, text, word) in samples) {
    testWidgets('$family: a double click selects a word', (tester) async {
      final (p, selected) = await show(tester, family, text);
      final where = at(tester, p, text.indexOf(word) + word.length ~/ 2);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: where);
      for (var i = 0; i < 2; i++) {
        await mouse.down(where);
        await tester.pump(const Duration(milliseconds: 20));
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
      expect(selected.value?.plainText, word);
    });

    testWidgets('$family: a drag selects along the curve', (tester) async {
      final (p, selected) = await show(tester, family, text);
      // From just before the first letter to the middle of the word: the text's start, into the word.
      final from = at(tester, p, 0, before: true), to = at(tester, p, text.indexOf(word) + word.length ~/ 2);
      final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var k = 1; k <= 8; k++) {
        await mouse.moveTo(Offset.lerp(from, to, k / 8)!);
        await tester.pump();
      }
      await mouse.up();
      await tester.pumpAndSettle();
      final got = selected.value?.plainText ?? '';
      expect(text.startsWith(got), isTrue, reason: '"$got"');
      expect(got.length, inInclusiveRange(text.indexOf(word) + 1, text.indexOf(word) + word.length - 1),
          reason: '"$got"');
    });

    testWidgets('$family: a long press selects a word and shows handles', (tester) async {
      final (p, selected) = await show(tester, family, text);
      await tester.longPressAt(at(tester, p, text.indexOf(word) + word.length ~/ 2));
      await tester.pumpAndSettle();
      expect(selected.value?.plainText, word);
      // The two handles follow leader layers pushed at the selection's ends.
      expect(find.byType(CompositedTransformFollower), findsAtLeastNWidgets(2));
    });

    testWidgets('$family: select all and copy', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      final (p, selected) = await show(tester, family, text);
      // Click into the text to give the selection area focus, then select all and copy.
      await tester.tapAt(at(tester, p, 0), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(selected.value?.plainText, text);
      expect(clipboard, text);
    });
  }
}
