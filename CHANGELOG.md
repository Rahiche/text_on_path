## 0.1.1

- Fixes a crash (a `RangeError` while shaping) for large text at a high pixel ratio, such as 140 px at 2 × the
  default oversample. The atlas a run is shaped with packed each cluster's cell in rows 4096 texels wide, which could
  stand taller than a GPU texture; the smaller image that came back was read as the size asked for. It now packs about
  as wide as tall and, when that wouldn't fit 8192 texels a side or 16M in all, is drawn at a lower density.
- An atlas for a zoomed view that can't be drawn falls back to the traced outlines instead of throwing.

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
