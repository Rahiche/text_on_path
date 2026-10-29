# text_on_path

Text along any curve in Flutter, a circle for a seal or any `Path`, with cursive scripts kept joined: Arabic, Persian
and Urdu letters stay connected; Devanagari and Bengali keep an unbroken headline.

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/bend.gif" alt="Hindi and Urdu on a circle that bends: each cluster turned rigidly opens the joins; text_on_path keeps them closed" width="720">
</p>

Text-on-path packages turn each glyph (or each character) whole to the curve. A joining stroke runs from one letter
into the next, so when the two turn by different angles it splits: a gap on the outside of a bend, an overlap on the
inside. Bending the whole run instead keeps joins closed but stretches every letter on the outside of a bend and
squashes it on the inside. text_on_path keeps letters rigid and bends only the rows they join on.

## Use

```sh
flutter pub add text_on_path
```

```dart
import 'package:text_on_path/text_on_path.dart';

TextOnPath(
  'الحروف تبقى متصلة',
  curve: PathCurve.arc(const Offset(160, 160), 120), // or PathCurve.fromPath(path)
  style: const TextStyle(fontSize: 32),
)
```

`TextOnPath` fills the space it's given; the curve is in its coordinates. Text stands on the curve's left: on a
clockwise circle it faces out, on an anticlockwise one it faces in. `position` places the middle of the text along the
curve, as a fraction of its length.

- **Fit a length**: `fit: TextOnPathFit.kashida` (Arabic's own way: one join a word drawn out, where a calligrapher
  would), `tracking` (joins drawn out rather than opened) or `spacing` (between words), to `fitLength`.
- **Compare**: `mode: TextOnPathMode.rigid` turns each cluster whole, as other packages do (but shaped); `warp` bends
  the whole run, as SVG's `textPath method="stretch"` would.
- **Sharp at any zoom**: by default the text is drawn from an atlas drawn again for the scale it's shown at (any
  `Transform` or `InteractiveViewer` above it, times the screen's pixel ratio), and from traced outlines past a memory
  budget. `rendering: TextOnPathRendering.vector` always uses outlines.

### As vectors: SVG and PDF

```dart
final shaped = await ShapedText.layout('शिरोरेखा जुड़ी रहती है', style);
final outlines = await TextOutlines.trace(shaped);
final placement = TextOnPathPlacement(shaped, curve);
final svg = placement.toSvg(outlines); // or placement.toPdf(outlines), placement.outlinePaths(outlines)
```

`ShapedText` shapes the text once; `TextOnPathPlacement` places it on a curve (cheap: once a frame if the curve moves)
and paints it, from an atlas or outlines; `TextOnPathMetrics.of(placement)` measures it.

## How it works

1. **Shape once.** The whole run is shaped by Flutter's paragraph engine, so every script comes out right: Arabic
   joining forms, Indic conjuncts and vowel signs, Nastaliq's slope.
2. **Draw each cluster alone.** Each grapheme cluster is drawn with the rest of the run transparent, so it keeps its
   exact shape and place, overhanging tails and all.
3. **Find the joining rows.** Wherever ink crosses the boundary between two clusters, that's a join; the rows most
   joins cross in are the script's connection line: the Arabic baseline stroke, the Indic headline.
4. **Bend only those rows.** Each cluster is a triangle mesh (`Canvas.drawVertices`). Points in the joining rows follow
   the curve; points away from them stand rigid with their letter; one eases into the other over 0.18 em.
5. **Draw joins out, or pull them shut.** Where rigid letters land apart along the curve, a flat join is drawn out with
   its own cross-section, as a tatweel would be; a sloping one is pulled shut, the pull fading out over 0.3 em.

## How well it works

At 48 px on a circle of radius 3 em, letters facing out. **Joins**: the area, in px², between where one cluster puts
a join's boundary and where its neighbour puts it, over the phrase. **Distortion**: how far ink moved from the nearest
rigid placement of its letter, RMS, in px. Both measured through the mesh as drawn.

| Sample | Joins, rigid | Joins, text_on_path | Distortion, plain warp | Distortion, text_on_path |
|---|---:|---:|---:|---:|
| Arabic (Noto Naskh Arabic) | 13 | 0 | 0.43 | 0.22 |
| Persian (Noto Naskh Arabic) | 7.8 | 0 | 0.29 | 0.18 |
| Urdu (Noto Nastaliq Urdu) | 62 | 0.1 | 1.32 | 0.43 |
| Hindi (Noto Sans Devanagari) | 135 | 0 | 1.51 | 0.28 |
| Bengali (Noto Sans Bengali) | 92 | 0 | 2.06 | 0.44 |
| Latin script (Dancing Script) | 51 | 0.1 | 0.49 | 0.18 |

Rigid placement's defects are all gaps outside a bend and all overlaps inside one. text_on_path closes them, with
between a fifth and two thirds of a plain warp's distortion. Fitted round a whole ring, rigid placement can only open
joins (221 px² on an Arabic seal); text_on_path draws them out. The inside of a bend, an S-curve and the seals are in
[doc/measurements.md](https://github.com/Rahiche/text_on_path/blob/main/doc/measurements.md), and the sharpness study
in [doc/sharpness.md](https://github.com/Rahiche/text_on_path/blob/main/doc/sharpness.md).

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/app_compare_end.png" alt="The example app: Hindi, Bengali and a Latin script hand on a circle and an S-curve, rigid placement beside joined, each measured, with a loupe on the widest join" width="720">
</p>

## The example app

`example/` shows Arabic, Persian, Urdu, Hindi, Bengali and a Latin script hand on a circle and an S-curve, rigid
placement beside joined, measured, with a loupe on the join rigid placement opens widest; seals fitted by kashida,
tracking or word spacing; and a zoomable view that saves SVG and PDF. Its fonts are bundled under the SIL Open Font
License.

## Limits

- On the inside of a bend, letters are spaced along whichever is nearer the inside, the baseline or the joining rows,
  so joins are never squeezed. For the Indic headline, well above the baseline, that makes Hindi and Bengali about a
  quarter longer inside a circle of radius 3 em.
- Flutter doesn't hand back glyph outlines, so `TextOutlines` traces them from a fine raster: within a few hundredths of
  a pixel of the font's edges at the text's size, but polygons, not the font's own curves.
- Kashida draws a join out with the stroke's own cross-section rather than inserting U+0640 and shaping again, so a
  font's special kashida forms don't appear.
- The joining rows are found from the run's pixels; `connection: ConnectionLine.between(...)` sets them by hand.

## License

Apache 2.0. The example's fonts are under the SIL Open Font License, Version 1.1.
