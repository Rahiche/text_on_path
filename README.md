# text_on_path

Text along any curve in Flutter, with cursive scripts kept joined. Arabic, Persian and Urdu stay connected; Hindi and
Bengali keep their headline.

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/bend.gif" alt="Hindi and Urdu on a circle that bends: each letter turned rigidly opens the joins; text_on_path keeps them closed" width="720">
</p>

<p align="center">
  <b><a href="https://rahiche.github.io/text_on_path/">Try it in your browser</a></b> ·
  <a href="https://github.com/Rahiche/text_on_path/blob/main/doc/getting_started.md">Get started</a>
</p>

## Why text_on_path

- **Joins stay closed.** Other packages turn each letter to the curve, so cursive joins break open. text_on_path bends
  only where letters join.
- **Letters keep their shape.** Warping the whole line stretches every letter; text_on_path distorts them a fifth to two
  thirds as much.
- **Every script Flutter shapes.** Arabic, Persian, Urdu Nastaliq, Hindi, Bengali and Latin script hands.
- **Seals that fit.** Fill a ring with kashida, tracking or word spacing, never by opening joins.
- **Selectable.** Drag, double-click and copy inside a `SelectionArea`, right to left too.
- **Sharp and exportable.** It stays crisp at any zoom, and exports to SVG and PDF.

## Demos

<table>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/selection.gif" alt="Selecting Arabic and Hindi on a curve" width="360"></td>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/seal.gif" alt="A seal filling as its joins are drawn out" width="360"></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/draw.gif" alt="Text following a curve drawn by hand" width="360"></td>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/seals.png" alt="Six seals, fitted by kashida, tracking or word spacing" width="360"></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_urdu.png" alt="Urdu on an arc and an S-curve" width="360"></td>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_bengali.png" alt="Bengali on an arc and an S-curve" width="360"></td>
  </tr>
</table>

## Learn more

- [Getting started](https://github.com/Rahiche/text_on_path/blob/main/doc/getting_started.md): install, options, selection, and SVG and PDF.
- [How it works](https://github.com/Rahiche/text_on_path/blob/main/doc/how_it_works.md): the method, the measurements and the limits.
- [Measurements](https://github.com/Rahiche/text_on_path/blob/main/doc/measurements.md) and
  [sharpness](https://github.com/Rahiche/text_on_path/blob/main/doc/sharpness.md), in full.

## License

Apache 2.0. The example's fonts are under the SIL Open Font License 1.1.
