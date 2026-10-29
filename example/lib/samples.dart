import 'package:flutter/widgets.dart';
import 'package:text_on_path/text_on_path.dart';

/// A phrase in one script, in a font bundled with this app.
class Sample {
  const Sample(this.name, this.font, this.family, this.text, this.meaning, this.fit, this.joinsOn);

  final String name, font, family, text, meaning;

  /// How it fills a longer path: kashida for Arabic and Persian, tracking for the Indic headlines, word spacing for
  /// Nastaliq and the Latin script hand.
  final TextOnPathFit fit;

  /// Where its letters join, in a few words.
  final String joinsOn;

  TextStyle style(double size, {Color color = const Color(0xff1d1a16)}) =>
      TextStyle(fontFamily: family, fontSize: size, color: color);
}

const samples = [
  Sample(
    'Arabic',
    'Noto Naskh Arabic',
    'Naskh',
    'الحروف تبقى متصلة',
    'The letters stay connected',
    TextOnPathFit.kashida,
    'on the baseline',
  ),
  Sample(
    'Persian',
    'Noto Naskh Arabic',
    'Naskh',
    'خیلی ممنون',
    'Thank you very much',
    TextOnPathFit.kashida,
    'on the baseline',
  ),
  Sample(
    'Urdu',
    'Noto Nastaliq Urdu',
    'Nastaliq',
    'بہت شکریہ',
    'Thank you very much',
    TextOnPathFit.spacing,
    'down a slope, each at its own height',
  ),
  Sample(
    'Hindi',
    'Noto Sans Devanagari',
    'Deva',
    'शिरोरेखा जुड़ी रहती है',
    'The headline stays joined',
    TextOnPathFit.tracking,
    'along the headline',
  ),
  Sample(
    'Bengali',
    'Noto Sans Bengali',
    'Beng',
    'বাংলা লিপির মাত্রা',
    'The headline of Bengali script',
    TextOnPathFit.tracking,
    'along the headline',
  ),
  Sample(
    'Latin script',
    'Dancing Script',
    'Dancing',
    'Handwriting stays joined',
    '',
    TextOnPathFit.spacing,
    'near the baseline, some higher',
  ),
];
