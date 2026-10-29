import 'package:flutter/widgets.dart';
import 'package:text_on_path/text_on_path.dart';

/// A script, in a font bundled with this app, with a few phrases to show it.
class Sample {
  const Sample(this.name, this.font, this.family, this.phrases, this.fit, this.joinsOn);

  final String name, font, family;

  /// Each phrase and what it means. The first is the one shown by default.
  final List<(String, String)> phrases;

  /// How it fills a longer path: kashida for Arabic and Persian, tracking for the Indic headlines, word spacing for
  /// Nastaliq and the Latin script hand.
  final TextOnPathFit fit;

  /// Where its letters join, in a few words.
  final String joinsOn;

  String get text => phrases.first.$1;
  String get meaning => phrases.first.$2;

  TextStyle style(double size, {Color color = const Color(0xff1d1a16)}) =>
      TextStyle(fontFamily: family, fontSize: size, color: color);
}

const samples = [
  Sample(
    'Arabic',
    'Noto Naskh Arabic',
    'Naskh',
    [
      ('الحروف تبقى متصلة', 'The letters stay connected'),
      ('مرحبا بالعالم', 'Hello, world'),
      ('الخط العربي فن جميل', 'Arabic calligraphy is a beautiful art'),
    ],
    TextOnPathFit.kashida,
    'on the baseline',
  ),
  Sample(
    'Persian',
    'Noto Naskh Arabic',
    'Naskh',
    [
      ('خیلی ممنون', 'Thank you very much'),
      ('سلام دنیا', 'Hello, world'),
      ('فارسی شکر است', 'Persian is sugar'),
    ],
    TextOnPathFit.kashida,
    'on the baseline',
  ),
  Sample(
    'Urdu',
    'Noto Nastaliq Urdu',
    'Nastaliq',
    [
      ('بہت شکریہ', 'Thank you very much'),
      ('خوش آمدید', 'Welcome'),
      ('اردو زبان', 'The Urdu language'),
    ],
    TextOnPathFit.spacing,
    'down a slope, each at its own height',
  ),
  Sample(
    'Hindi',
    'Noto Sans Devanagari',
    'Deva',
    [
      ('शिरोरेखा जुड़ी रहती है', 'The headline stays joined'),
      ('नमस्ते दुनिया', 'Hello, world'),
      ('हिन्दी भाषा', 'The Hindi language'),
    ],
    TextOnPathFit.tracking,
    'along the headline',
  ),
  Sample(
    'Bengali',
    'Noto Sans Bengali',
    'Beng',
    [
      ('বাংলা লিপির মাত্রা', 'The headline of Bengali script'),
      ('শুভ সকাল', 'Good morning'),
      ('বাংলা ভাষা', 'The Bengali language'),
    ],
    TextOnPathFit.tracking,
    'along the headline',
  ),
  Sample(
    'Latin script',
    'Dancing Script',
    'Dancing',
    [
      ('Handwriting stays joined', ''),
      ('Hello from Flutter', ''),
      ('Text on a curve', ''),
    ],
    TextOnPathFit.spacing,
    'near the baseline, some higher',
  ),
];
