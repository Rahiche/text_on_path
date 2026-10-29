/// Text laid along a curve with cursive joins kept closed: Arabic letters stay connected along the baseline, and
/// Devanagari and Bengali keep an unbroken headline.
library;

export 'src/curve.dart' show PathCurve;
export 'src/metrics.dart';
export 'src/outline.dart';
export 'src/placement.dart' show TextOnPathMode, TextOnPathFit, TextOnPathPlacement;
export 'src/shaped_text.dart' show ShapedText, TextAtlas, TextUnit, UnitPair, ConnectionBand, ConnectionLine;
export 'src/widget.dart';
