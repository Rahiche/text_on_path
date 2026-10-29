## 0.1.0

- `TextOnPath`: text along a `PathCurve` (any `Path`, or a circular arc for a seal), cursive joins kept closed. Arabic,
  Persian and Urdu stay connected; Devanagari and Bengali keep their headline.
- Joined placement: letters stand rigid, and only the rows they join on follow the curve. A widened join is drawn out
  along the curve; a sloping one (Nastaliq, a script hand) is pulled shut. Rigid and plain-warp placements to compare.
- Fitting to a length: kashida for Arabic, tracking that draws joins out rather than opening them, or word spacing.
- Sharp at any zoom: the atlas is drawn again for the scale the text is shown at, and past a memory budget the text is
  drawn from traced outlines (`TextOnPathRendering`).
- `TextOutlines` and `TextOnPathPlacement.toSvg` / `toPdf`: the placed text as vectors.
- Selection inside a `SelectionArea`: drag, double-click a word, long-press for handles, copy. Positions come from the
  straight line the text was shaped as; the highlight bends with the curve and the handles turn with it.
- `TextOnPathMetrics`: the area of gaps and overlaps at joins, how many joins visibly open, and how far letters were
  distorted.
