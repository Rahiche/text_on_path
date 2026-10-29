# Getting started

## Install

```sh
flutter pub add text_on_path
```

Needs Flutter 3.29 or later.

## Text on a curve

```dart
import 'package:text_on_path/text_on_path.dart';

TextOnPath(
  'الحروف تبقى متصلة',
  curve: PathCurve.arc(const Offset(160, 160), 120), // or PathCurve.fromPath(path)
  style: const TextStyle(fontSize: 32),
)
```

`TextOnPath` fills the space it's given, and the curve is in its coordinates. The text stands on the curve's left: on
a clockwise circle it faces out, and on an anticlockwise one it faces in. `position` places the middle of the text
along the curve, as a fraction of its length.

## Options

- **Fit a length:** `fit:` fills `fitLength`, which is otherwise the curve's whole length. The choices are:
  - `TextOnPathFit.kashida`, Arabic's own way: one join a word drawn out, where a calligrapher would;
  - `tracking`, which draws joins out rather than opening them;
  - `spacing`, between words.
- **Compare:** `mode:` is `TextOnPathMode.joined` by default.
  - `rigid` turns each cluster whole, as other packages do (but shaped).
  - `warp` bends the whole run, as SVG's `textPath method="stretch"` would.
- **Sharpness:** by default the text is drawn from an atlas, drawn again for the scale it's shown at. That scale counts
  any `Transform` or `InteractiveViewer` above it, times the screen's pixel ratio. Past a memory budget, it's drawn
  from traced outlines instead. `rendering: TextOnPathRendering.vector` always uses outlines.
- **Joining rows:** they're found from the text's pixels; `connection: ConnectionLine.between(...)` sets them by hand.

## Selection

Inside a `SelectionArea`, curved text selects like any other: drag across it, double-click a word, long-press on a
phone for handles, and copy.

```dart
SelectionArea(
  child: TextOnPath('الحروف تبقى متصلة', curve: curve, style: style),
)
```

## SVG and PDF

```dart
final shaped = await ShapedText.layout('शिरोरेखा जुड़ी रहती है', style);
final outlines = await TextOutlines.trace(shaped);
final placement = TextOnPathPlacement(shaped, curve);
final svg = placement.toSvg(outlines); // or placement.toPdf(outlines), placement.outlinePaths(outlines)
```

The lower-level classes are useful for painting the text yourself:
- `ShapedText` shapes the text once.
- `TextOnPathPlacement` places it on a curve. That's cheap enough to do every frame if the curve moves. It paints from
  an atlas or from outlines.
- `TextOnPathMetrics.of(placement)` measures the joins and the distortion.

## The example app

`example/` is the [gallery](https://rahiche.github.io/text_on_path/). It also runs on the desktop and on phones.

```sh
cd example && flutter run
```

Its fonts are bundled under the SIL Open Font License.

## Next

- [How it works](how_it_works.md): the method, the measurements and the limits.
- [Measurements](measurements.md) and [sharpness](sharpness.md) in full.
