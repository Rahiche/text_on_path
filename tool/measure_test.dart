// Measures every sample in every placement and writes doc/measurements.md and the pictures in doc/images/.
//
// Run from the package's folder:
//   flutter test tool/measure_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_on_path/text_on_path.dart';

/// (name, family, font file, font name, text, meaning, fit)
const samples = <(String, String, String, String, String, String, TextOnPathFit)>[
  (
    'Arabic',
    'Naskh',
    'NotoNaskhArabic.ttf',
    'Noto Naskh Arabic',
    'الحروف تبقى متصلة',
    'The letters stay connected',
    TextOnPathFit.kashida
  ),
  (
    'Persian',
    'Naskh',
    'NotoNaskhArabic.ttf',
    'Noto Naskh Arabic',
    'خیلی ممنون',
    'Thank you very much',
    TextOnPathFit.kashida
  ),
  (
    'Urdu',
    'Nastaliq',
    'NotoNastaliqUrdu.ttf',
    'Noto Nastaliq Urdu',
    'بہت شکریہ',
    'Thank you very much',
    TextOnPathFit.spacing
  ),
  (
    'Hindi',
    'Deva',
    'NotoSansDevanagari.ttf',
    'Noto Sans Devanagari',
    'शिरोरेखा जुड़ी रहती है',
    'The headline stays joined',
    TextOnPathFit.tracking
  ),
  (
    'Bengali',
    'Beng',
    'NotoSansBengali.ttf',
    'Noto Sans Bengali',
    'বাংলা লিপির মাত্রা',
    'The headline of Bengali script',
    TextOnPathFit.tracking
  ),
  (
    'Latin script',
    'Dancing',
    'DancingScript.ttf',
    'Dancing Script',
    'Handwriting stays joined',
    '',
    TextOnPathFit.spacing
  ),
];

const fontSize = 48.0;
const atlasScale = 4.0; // Texels per logical pixel: a 2x screen with the default oversampling of 2.
const imageScale = 1.0;
const ink = Color(0xff1d1a16);

Future<void> loadFont(String family, String file) async {
  final bytes = File('example/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// A curve to measure on, built round the origin.
typedef CurveCase = ({String name, String note, PathCurve curve});

List<CurveCase> curvesFor(ShapedText shaped) {
  const r = 3 * fontSize;
  final w = shaped.width * 1.15;
  return [
    (
      name: 'outside a circle',
      note: 'radius 3 em, letters facing out: joins on the outside of the bend',
      curve: PathCurve.arc(Offset.zero, r),
    ),
    (
      name: 'inside a circle',
      note: 'radius 3 em, letters facing in, as along the bottom of a seal: joins on the inside of the bend',
      curve: PathCurve.arc(Offset.zero, r, startAngle: -math.pi / 2, sweepAngle: -2 * math.pi),
    ),
    (
      name: 'S-curve',
      note: 'a cubic Bézier Path, 1.15 times the text\'s width, bending both ways',
      curve: PathCurve.fromPath(
        Path()
          ..moveTo(-w / 2, 0)
          ..cubicTo(-w / 6, -0.45 * w, w / 6, 0.45 * w, w / 2, 0),
      ),
    ),
  ];
}

/// The area the placed text covers, from its ink's outline.
Rect bounds(TextOnPathPlacement p) {
  var box = Rect.zero;
  var first = true;
  for (var i = 0; i < p.text.units.length; i++) {
    final ink = p.text.units[i].ink;
    if (ink.isEmpty) continue;
    for (var k = 0; k <= 8; k++) {
      for (final (x, y) in [
        (ink.left + ink.width * k / 8, ink.top),
        (ink.left + ink.width * k / 8, ink.bottom),
        (ink.left, ink.top + ink.height * k / 8),
        (ink.right, ink.top + ink.height * k / 8),
      ]) {
        final o = p.map(i, x, y);
        box = first ? Rect.fromPoints(o, o) : box.expandToInclude(Rect.fromPoints(o, o));
        first = false;
      }
    }
  }
  return box;
}

/// Draws [placements] side by side, each cropped to the same [frame], on white.
Future<void> picture(String path, List<List<TextOnPathPlacement>> grid, List<Rect> frames,
    {Color background = const Color(0xffffffff), void Function(Canvas, int column)? under}) async {
  const gap = 16.0;
  final width = frames.fold(0.0, (a, f) => a + f.width) + gap * (frames.length + 1);
  final rowHeight = frames.fold(0.0, (a, f) => math.max(a, f.height));
  final height = rowHeight * grid.length + gap * (grid.length + 1);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(imageScale);
  canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = background);
  for (var r = 0; r < grid.length; r++) {
    var x = gap;
    for (var c = 0; c < frames.length; c++) {
      final f = frames[c];
      canvas
        ..save()
        ..translate(x, gap + r * (rowHeight + gap) + (rowHeight - f.height) / 2)
        ..clipRect(Offset.zero & f.size)
        ..translate(-f.left, -f.top);
      under?.call(canvas, c);
      canvas.drawPath(
        grid[r][c].curve.toPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x1f000000),
      );
      grid[r][c].paint(canvas);
      canvas.restore();
      x += f.width + gap;
    }
  }
  final image = await recorder.endRecording().toImage((width * imageScale).ceil(), (height * imageScale).ceil());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

String area(double a) => a < 0.05 ? '0' : a.toStringAsFixed(a < 10 ? 1 : 0);
String px(double d) => d.toStringAsFixed(2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measure', () async {
    Directory('doc/images').createSync(recursive: true);
    for (final s in samples) {
      await loadFont(s.$2, s.$3);
    }
    final table = <String, List<String>>{};
    final seals = <String>[];
    final notes = <String>[];

    for (final (name, family, _, font, text, meaning, fit) in samples) {
      final style = TextStyle(fontFamily: family, fontSize: fontSize, color: ink);
      final shaped = await ShapedText.layout(text, style, scale: atlasScale);
      final joins = shaped.neighbours.where((p) => p.joins).length;
      final inBand = shaped.neighbours.where((p) => p.joins && p.inBand).length;
      notes.add('| $name | ${meaning.isEmpty ? text : '$text ($meaning)'} | $font | ${shaped.units.length} | $joins | '
          '$inBand | '
          '${shaped.band == null ? '-' : '${((shaped.baseline - shaped.band!.bottom) / fontSize).toStringAsFixed(2)}'
              '–${((shaped.baseline - shaped.band!.top) / fontSize).toStringAsFixed(2)} em'} |');

      final cases = curvesFor(shaped);
      final grid = <List<TextOnPathPlacement>>[[], []];
      final frames = <Rect>[];
      for (final c in cases) {
        final m = {
          for (final mode in TextOnPathMode.values)
            mode: TextOnPathMetrics.of(TextOnPathPlacement(shaped, c.curve, mode: mode)),
        };
        final rigid = m[TextOnPathMode.rigid]!, warp = m[TextOnPathMode.warp]!, joined = m[TextOnPathMode.joined]!;
        final r = TextOnPathPlacement(shaped, c.curve, mode: TextOnPathMode.rigid);
        final j = TextOnPathPlacement(shaped, c.curve, mode: TextOnPathMode.joined);
        final longer = 100 * (j.length / r.length - 1);
        (table[c.name] ??= []).add(
          '| $name | **${area(rigid.joinArea)}** (${area(rigid.gapArea)} / ${area(rigid.overlapArea)}) | '
          '${area(warp.joinArea)} | **${area(joined.joinArea)}** | '
          '${px(rigid.distortion)} | **${px(warp.distortion)}** | **${px(joined.distortion)}** | '
          '${longer.abs() < 0.5 ? 'same' : '${longer > 0 ? '+' : ''}${longer.round()}%'} |',
        );
        grid[0].add(r);
        grid[1].add(j);
        frames.add(bounds(r).expandToInclude(bounds(j)).inflate(8));
      }
      final file = name.toLowerCase().replaceAll(' ', '_');
      await picture('doc/images/$file.png', grid, frames);

      // A seal: the phrase twice round a whole ring, fitted to it.
      final phrase = '$text   $text   ';
      const red = Color(0xff9c1d15);
      final sealText = await ShapedText.layout(phrase, style.copyWith(color: red, fontSize: 40), scale: atlasScale);
      final ringRadius = sealText.width / (2 * math.pi * 0.86);
      final ring = PathCurve.arc(Offset.zero, ringRadius);
      final fitted = [
        for (final mode in [TextOnPathMode.rigid, TextOnPathMode.joined])
          TextOnPathPlacement(sealText, ring, mode: mode, fit: fit, fitLength: ring.length - sealText.fontSize),
      ];
      final sm = [for (final p in fitted) TextOnPathMetrics.of(p)];
      seals.add('| $name | ${fit.name} | ${(ringRadius / 40).toStringAsFixed(1)} em | '
          '${(100 * (fitted[1].length / fitted[1].naturalLength - 1)).round()}% | '
          '**${area(sm[0].joinArea)}** | **${area(sm[1].joinArea)}** | ${px(sm[1].distortion)} |');
      var up = 0.0, down = 0.0;
      for (final u in sealText.units) {
        up = math.max(up, sealText.baseline - u.ink.top);
        down = math.max(down, u.ink.bottom - sealText.baseline);
      }
      final outer = ringRadius + up + 8, inner = ringRadius - down - 8;
      final frame = Rect.fromCircle(center: Offset.zero, radius: outer + 10);
      await picture(
        'doc/images/seal_$file.png',
        [fitted],
        [frame, frame],
        background: const Color(0xfffffbf4),
        under: (canvas, _) {
          final p = Paint()
            ..style = PaintingStyle.stroke
            ..color = red;
          canvas
            ..drawCircle(Offset.zero, outer, p..strokeWidth = 2.5)
            ..drawCircle(Offset.zero, inner, p..strokeWidth = 1.5);
        },
      );
      sealText.dispose();
      shaped.dispose();
    }

    final cases = curvesFor((await ShapedText.layout('a', const TextStyle(fontSize: 10))));
    final out = StringBuffer()
      ..writeln('# Measurements')
      ..writeln()
      ..writeln('Written by `flutter test tool/measure_test.dart`. Every sample at ${fontSize.round()} px, its atlas '
          'drawn at ${atlasScale.round()} texels per pixel. Each placement is measured as drawn: through its mesh, the '
          'way the GPU interpolates it, not through the formula that built the mesh.')
      ..writeln()
      ..writeln('- **Joins**: wherever a stroke runs from one cluster into the next, each cluster carries its own copy '
          'of the boundary between them. The area between the two copies is a gap where they pull apart and an overlap '
          'where they cross, in px², summed over every join of the phrase.')
      ..writeln('- **Distortion**: each cluster\'s ink is compared with the closest rigid placement of the same letter '
          '(best rotation and shift, by least squares). The root mean square distance over all the ink, in px.')
      ..writeln()
      ..writeln('On the inside of a bend, joined placement spaces letters along whichever is nearer the inside, the '
          'baseline or the joining rows, so a join is only ever drawn out, never squeezed. For the Indic headline, '
          'well above the baseline, that makes the text longer there: the last column.')
      ..writeln()
      ..writeln('Rigid per-glyph placement is the best a rigid approach can do: the run is shaped as a whole, so '
          'every letter has its joining form, and each cluster is turned whole to the curve at the middle of its '
          'box. (Packages on pub.dev place characters one by one, so Arabic loses its joining forms before any of '
          'this.) Plain warp bends the whole run along the curve\'s normals, as SVG\'s `textPath method="stretch"` '
          'would.')
      ..writeln()
      ..writeln('## The samples')
      ..writeln()
      ..writeln('| Sample | Text | Font | Clusters | Joins | On the joining rows | Joining rows (above the baseline) |')
      ..writeln('|---|---|---|---:|---:|---:|---|');
    notes.forEach(out.writeln);
    for (final c in cases) {
      out
        ..writeln()
        ..writeln('## ${c.name[0].toUpperCase()}${c.name.substring(1)}')
        ..writeln()
        ..writeln('${c.note[0].toUpperCase()}${c.note.substring(1)}.')
        ..writeln()
        ..writeln('| Sample | Joins, rigid (gap / overlap) | Joins, warp | Joins, joined | Distortion, rigid | '
            'Distortion, warp | Distortion, joined | Length, joined against rigid |')
        ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
      table[c.name]!.forEach(out.writeln);
    }
    out
      ..writeln()
      ..writeln('## Seals: fitted to a whole ring')
      ..writeln()
      ..writeln('Each phrase twice round a ring, stretched to fill it but for one em: kashida for Arabic and Persian, '
          'tracking for Hindi and Bengali, word spacing for Urdu and the Latin script hand. Rigid placement can only '
          'open gaps to add length; joined placement draws the joining stroke out along the curve instead.')
      ..writeln()
      ..writeln('| Sample | Fit | Ring radius | Stretched by | Joins, rigid | Joins, joined | Distortion, joined |')
      ..writeln('|---|---|---:|---:|---:|---:|---:|');
    seals.forEach(out.writeln);
    File('doc/measurements.md').writeAsStringSync(out.toString());
    stdout.write(out);
  });
}
