# text_on_path

Text along any curve in Flutter, with cursive scripts kept joined.

**[Try it in your browser →](https://rahiche.github.io/text_on_path/)**

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/bend.gif" alt="Hindi and Urdu on a circle that bends: each cluster turned rigidly opens the joins; text_on_path keeps them closed" width="720">
</p>

Turning each letter to the curve breaks the joins. Bending the whole line stretches the letters. text_on_path keeps
letters rigid and bends only where they join.

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/schematic.png" alt="Each letter turned whole splits the headline; the whole line bent stretches the letters; only the joining rows bent keeps both" width="720">
</p>

## Use

```sh
flutter pub add text_on_path
```

```dart
TextOnPath(
  'الحروف تبقى متصلة',
  curve: PathCurve.arc(const Offset(160, 160), 120), // or PathCurve.fromPath(path)
  style: const TextStyle(fontSize: 32),
)
```

- `fit:` fills a length with kashida, tracking or word spacing.
- `mode:` switches to `rigid` or `warp`, for comparison.
- Inside a `SelectionArea`, it selects like any text: drag, double-click, handles, copy.
- `TextOnPathPlacement.toSvg` and `toPdf` export vectors.

## Scripts

<table>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_arabic.png" alt="Arabic" width="360"></td>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_persian.png" alt="Persian" width="360"></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_urdu.png" alt="Urdu" width="360"></td>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_hindi.png" alt="Hindi" width="360"></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_bengali.png" alt="Bengali" width="360"></td>
    <td><img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/gallery_latin_script.png" alt="A Latin script hand" width="360"></td>
  </tr>
</table>

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/text_on_path/main/doc/images/seals.png" alt="Six seals, each fitted round a ring by kashida, tracking or word spacing" width="720">
</p>

## More

- On a 3 em circle, letter-by-letter placement leaves 8 to 135 px² of gaps at the joins. text_on_path leaves at most
  0.1, and distorts letters a fifth to two thirds as much as a warp.
- [How it works](https://github.com/Rahiche/text_on_path/blob/main/doc/how_it_works.md) covers the method, the
  measurements and the limits.

## License

Apache 2.0. The example's fonts are under the SIL Open Font License 1.1.
