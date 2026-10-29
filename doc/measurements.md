# Measurements

Written by `flutter test tool/measure_test.dart`. Every sample at 48 px, its atlas drawn at 4 texels per pixel. Each placement is measured as drawn: through its mesh, the way the GPU interpolates it, not through the formula that built the mesh.

- **Joins**: wherever a stroke runs from one cluster into the next, each cluster carries its own copy of the boundary between them. The area between the two copies is a gap where they pull apart and an overlap where they cross, in px², summed over every join of the phrase.
- **Distortion**: each cluster's ink is compared with the closest rigid placement of the same letter (best rotation and shift, by least squares). The root mean square distance over all the ink, in px.

On the inside of a bend, joined placement spaces letters along whichever is nearer the inside, the baseline or the joining rows, so a join is only ever drawn out, never squeezed. For the Indic headline, well above the baseline, that makes the text longer there: the last column.

Rigid per-glyph placement is the best a rigid approach can do: the run is shaped as a whole, so every letter has its joining form, and each cluster is turned whole to the curve at the middle of its box. (Packages on pub.dev place characters one by one, so Arabic loses its joining forms before any of this.) Plain warp bends the whole run along the curve's normals, as SVG's `textPath method="stretch"` would.

## The samples

| Sample | Text | Font | Clusters | Joins | On the joining rows | Joining rows (above the baseline) |
|---|---|---|---:|---:|---:|---|
| Arabic | الحروف تبقى متصلة (The letters stay connected) | Noto Naskh Arabic | 15 | 9 | 9 | 0.01–0.09 em |
| Persian | خیلی ممنون (Thank you very much) | Noto Naskh Arabic | 9 | 6 | 6 | 0.01–0.09 em |
| Urdu | بہت شکریہ (Thank you very much) | Noto Nastaliq Urdu | 8 | 5 | 4 | 0.31–0.49 em |
| Hindi | शिरोरेखा जुड़ी रहती है (The headline stays joined) | Noto Sans Devanagari | 10 | 6 | 6 | 0.55–0.63 em |
| Bengali | বাংলা লিপির মাত্রা (The headline of Bengali script) | Noto Sans Bengali | 7 | 3 | 3 | 0.55–0.63 em |
| Latin script | Handwriting stays joined | Dancing Script | 22 | 18 | 17 | 0.06–0.13 em |

## Outside a circle

Radius 3 em, letters facing out: joins on the outside of the bend.

| Sample | Joins, rigid (gap / overlap) | Joins, warp | Joins, joined | Distortion, rigid | Distortion, warp | Distortion, joined | Length, joined against rigid |
|---|---:|---:|---:|---:|---:|---:|---:|
| Arabic | **13** (13 / 0) | 0 | **0** | 0.00 | **0.43** | **0.22** | same |
| Persian | **7.8** (7.8 / 0) | 0 | **0** | 0.00 | **0.29** | **0.18** | same |
| Urdu | **62** (62 / 0) | 0 | **0.1** | 0.00 | **1.32** | **0.43** | same |
| Hindi | **135** (135 / 0) | 0 | **0** | 0.00 | **1.51** | **0.28** | same |
| Bengali | **92** (92 / 0) | 0 | **0** | 0.00 | **2.06** | **0.44** | same |
| Latin script | **51** (51 / 0) | 0 | **0.1** | 0.00 | **0.49** | **0.18** | same |

## Inside a circle

Radius 3 em, letters facing in, as along the bottom of a seal: joins on the inside of the bend.

| Sample | Joins, rigid (gap / overlap) | Joins, warp | Joins, joined | Distortion, rigid | Distortion, warp | Distortion, joined | Length, joined against rigid |
|---|---:|---:|---:|---:|---:|---:|---:|
| Arabic | **9.7** (0 / 9.7) | 0 | **0** | 0.00 | **0.43** | **0.22** | +2% |
| Persian | **6.3** (0 / 6.3) | 0 | **0** | 0.00 | **0.29** | **0.18** | +2% |
| Urdu | **59** (0.1 / 59) | 0 | **0.1** | 0.00 | **1.31** | **0.55** | +15% |
| Hindi | **129** (0 / 129) | 0 | **0** | 0.00 | **1.52** | **0.42** | +24% |
| Bengali | **85** (0 / 85) | 0 | **0** | 0.00 | **2.08** | **0.65** | +24% |
| Latin script | **47** (0 / 47) | 0 | **0** | 0.00 | **0.49** | **0.16** | +3% |

## S-curve

A cubic Bézier Path, 1.15 times the text's width, bending both ways.

| Sample | Joins, rigid (gap / overlap) | Joins, warp | Joins, joined | Distortion, rigid | Distortion, warp | Distortion, joined | Length, joined against rigid |
|---|---:|---:|---:|---:|---:|---:|---:|
| Arabic | **12** (8.9 / 3.5) | 0 | **0** | 0.00 | **0.46** | **0.27** | +1% |
| Persian | **8.5** (3.7 / 4.8) | 0 | **0** | 0.00 | **0.63** | **0.36** | +1% |
| Urdu | **109** (32 / 77) | 0 | **0.2** | 0.00 | **1.44** | **0.57** | +13% |
| Hindi | **119** (82 / 37) | 0 | **0** | 0.00 | **1.74** | **0.33** | +10% |
| Bengali | **54** (0.6 / 54) | 0 | **0** | 0.00 | **2.29** | **0.61** | +11% |
| Latin script | **35** (22 / 13) | 0 | **0.1** | 0.00 | **0.57** | **0.16** | +1% |

## Seals: fitted to a whole ring

Each phrase twice round a ring, stretched to fill it but for one em: kashida for Arabic and Persian, tracking for Hindi and Bengali, word spacing for Urdu and the Latin script hand. Rigid placement can only open gaps to add length; joined placement draws the joining stroke out along the curve instead.

| Sample | Fit | Ring radius | Stretched by | Joins, rigid | Joins, joined | Distortion, joined |
|---|---|---:|---:|---:|---:|---:|
| Arabic | kashida | 2.9 em | 10% | **221** | **0** | 0.19 |
| Persian | kashida | 1.9 em | 6% | **100** | **0** | 0.24 |
| Urdu | spacing | 1.6 em | 4% | **169** | **0.3** | 0.64 |
| Hindi | tracking | 3.1 em | 10% | **341** | **0** | 0.23 |
| Bengali | tracking | 3.0 em | 10% | **237** | **0** | 0.38 |
| Latin script | spacing | 3.6 em | 11% | **56** | **0.1** | 0.12 |
