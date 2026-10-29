import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PathCurve', () {
    test('an arc has its length, ends, tangents and curvature', () {
      final arc = PathCurve.arc(const Offset(100, 100), 50, startAngle: 0, sweepAngle: math.pi);
      expect(arc.length, closeTo(50 * math.pi, 1e-6));
      expect(arc.closed, isFalse);
      expect(arc.pointAt(0), offsetMoreOrLessEquals(const Offset(150, 100)));
      expect(arc.pointAt(arc.length / 2), offsetMoreOrLessEquals(const Offset(100, 150), epsilon: 1e-3));
      // Clockwise on a canvas: from the right, heading down.
      expect(arc.tangentAt(0), offsetMoreOrLessEquals(const Offset(0, 1), epsilon: 1e-3));
      expect(arc.curvatureAt(10), closeTo(1 / 50, 1e-9));
    });

    test('a full turn is closed and wraps', () {
      final ring = PathCurve.arc(Offset.zero, 30);
      expect(ring.closed, isTrue);
      expect(ring.pointAt(ring.length + 5), offsetMoreOrLessEquals(ring.pointAt(5), epsilon: 1e-6));
    });

    test('a Path is sampled smoothly', () {
      final line = PathCurve.fromPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(200, 0),
      );
      expect(line.length, closeTo(200, 1e-3));
      expect(line.tangentAt(50), offsetMoreOrLessEquals(const Offset(1, 0), epsilon: 1e-6));
      expect(line.curvatureAt(50), closeTo(0, 1e-9));
      // Past an open end, it carries on straight.
      expect(line.pointAt(210), offsetMoreOrLessEquals(const Offset(210, 0), epsilon: 1e-3));

      final circle = PathCurve.fromPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 80)));
      expect(circle.closed, isTrue);
      expect(circle.length, closeTo(2 * math.pi * 80, 0.5));
      for (final d in [10.0, 120.0, 300.0]) {
        expect(circle.curvatureAt(d), closeTo(1 / 80, 1e-3));
      }
    });
  });

  group('placement', () {
    late ShapedText arabic, hindi;

    setUpAll(() async {
      await loadFont('Naskh', 'NotoNaskhArabic.ttf');
      await loadFont('Deva', 'NotoSansDevanagari.ttf');
      arabic = await ShapedText.layout('الحروف تبقى متصلة', const TextStyle(fontFamily: 'Naskh', fontSize: 40));
      hindi = await ShapedText.layout('शिरोरेखा जुड़ी रहती है', const TextStyle(fontFamily: 'Deva', fontSize: 40));
    });

    tearDownAll(() {
      arabic.dispose();
      hindi.dispose();
    });

    test('finds where each script joins', () {
      expect(arabic.textDirection, TextDirection.rtl);
      expect(arabic.neighbours.where((p) => p.joins), hasLength(9));
      // The Arabic baseline stroke, just above the baseline.
      expect(arabic.baseline - arabic.band!.bottom, lessThan(0.05 * 40));
      // The Devanagari headline, well above it.
      expect((hindi.baseline - hindi.band!.center) / 40, inInclusiveRange(0.5, 0.7));
    });

    test('on a straight line every mode is the flat run, moved', () {
      final line = PathCurve.fromPath(
        Path()
          ..moveTo(0, 100)
          ..lineTo(600, 100),
      );
      for (final mode in TextOnPathMode.values) {
        final p = TextOnPathPlacement(hindi, line, mode: mode);
        final m = TextOnPathMetrics.of(p);
        expect(m.joinArea, lessThan(0.5), reason: '$mode');
        expect(m.distortion, lessThan(0.05), reason: '$mode');
        // Same shift for every point: the flat run, translated.
        final shift = p.map(0, 0, 0) - Offset.zero;
        expect(p.map(3, 120, 30) - const Offset(120, 30), offsetMoreOrLessEquals(shift, epsilon: 0.05));
      }
    });

    test('rigid opens joins outside a bend and overlaps them inside; joined closes both', () {
      final outside = PathCurve.arc(Offset.zero, 120);
      final inside = PathCurve.arc(Offset.zero, 120, startAngle: -math.pi / 2, sweepAngle: -2 * math.pi);
      for (final text in [arabic, hindi]) {
        final out = TextOnPathMetrics.of(TextOnPathPlacement(text, outside, mode: TextOnPathMode.rigid));
        final into = TextOnPathMetrics.of(TextOnPathPlacement(text, inside, mode: TextOnPathMode.rigid));
        expect(out.gapArea, greaterThan(5));
        expect(out.overlapArea, lessThan(0.5));
        expect(into.overlapArea, greaterThan(5));
        expect(into.gapArea, lessThan(0.5));
        for (final curve in [outside, inside]) {
          final joined = TextOnPathMetrics.of(TextOnPathPlacement(text, curve, mode: TextOnPathMode.joined));
          final warp = TextOnPathMetrics.of(TextOnPathPlacement(text, curve, mode: TextOnPathMode.warp));
          expect(joined.joinArea, lessThan(1));
          expect(joined.distortion, lessThan(0.75 * warp.distortion));
        }
      }
    });

    test('fitting fills the length; kashida draws joins out instead of opening them', () {
      final ring = PathCurve.arc(Offset.zero, 160);
      final target = arabic.width * 1.3;
      final joined = TextOnPathPlacement(
        arabic,
        ring,
        mode: TextOnPathMode.joined,
        fit: TextOnPathFit.kashida,
        fitLength: target,
      );
      final rigid = TextOnPathPlacement(
        arabic,
        ring,
        mode: TextOnPathMode.rigid,
        fit: TextOnPathFit.kashida,
        fitLength: target,
      );
      expect(joined.length, closeTo(target, 0.5));
      expect(joined.overflows, isFalse);
      expect(TextOnPathMetrics.of(joined).joinArea, lessThan(1));
      expect(TextOnPathMetrics.of(rigid).gapArea, greaterThan(50));
    });

    test('the mesh is drawable', () {
      final p = TextOnPathPlacement(hindi, PathCurve.arc(Offset.zero, 150), mode: TextOnPathMode.joined);
      final vertices = p.vertices();
      expect(vertices, isNotEmpty);
      for (final v in vertices) {
        v.dispose();
      }
    });
  });

  testWidgets('the widget shapes, then paints, zoomed or not, from an atlas or outlines', (tester) async {
    await tester.runAsync(() => loadFont('Deva', 'NotoSansDevanagari.ttf'));
    for (final (zoom, rendering) in [
      (1.0, TextOnPathRendering.auto),
      (6.0, TextOnPathRendering.auto),
      (1.0, TextOnPathRendering.vector),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Transform.scale(
            scale: zoom,
            child: SizedBox(
              width: 400,
              height: 400,
              child: TextOnPath(
                'शिरोरेखा',
                key: ValueKey((zoom, rendering)),
                curve: PathCurve.arc(const Offset(200, 200), 120),
                style: const TextStyle(fontFamily: 'Deva', fontSize: 32),
                fit: TextOnPathFit.tracking,
                fitLength: 300,
                rendering: rendering,
              ),
            ),
          ),
        ),
      );
      // Shaping, drawing an atlas for the zoom and tracing all happen off the frame: let them finish between frames.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
      final drawn = find.descendant(
        of: find.byType(TextOnPath),
        matching: find.byWidgetPredicate((w) => w is LeafRenderObjectWidget),
      );
      expect(drawn, findsOneWidget, reason: '$zoom× $rendering');
      expect(tester.takeException(), isNull);
    }
  });

  test('outlines trace each cluster, and export as SVG and PDF', () async {
    await loadFont('Naskh', 'NotoNaskhArabic.ttf');
    final shaped = await ShapedText.layout('خیلی ممنون', const TextStyle(fontFamily: 'Naskh', fontSize: 40));
    final outlines = await TextOutlines.trace(shaped);
    expect(outlines.contours, hasLength(shaped.units.length));
    expect(outlines.contours.every((c) => c.isNotEmpty), isTrue);
    final placement = TextOnPathPlacement(
      shaped,
      PathCurve.arc(Offset.zero, 120),
      fit: TextOnPathFit.kashida,
      fitLength: shaped.width * 1.2,
    );
    final svg = placement.toSvg(outlines);
    expect(svg, startsWith('<svg'));
    // A path for each cluster, and one for each kashida bridge.
    expect('<path'.allMatches(svg).length, greaterThan(shaped.units.length));
    final pdf = String.fromCharCodes(placement.toPdf(outlines));
    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf.trimRight(), endsWith('%%EOF'));
    // The cross-reference table points at each object.
    final offset = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(pdf)!.group(1)!);
    expect(pdf.substring(offset), startsWith('xref'));
    for (final m in RegExp(r'(\d{10}) 00000 n').allMatches(pdf)) {
      expect(pdf.substring(int.parse(m.group(1)!)), matches(RegExp(r'^\d+ 0 obj')));
    }
    shaped.dispose();
  });
}
