import '../scanner.dart';

/// Unicode script categories detected by [LanguageScanner].
enum UnicodeScript {
  latin,
  cyrillic,
  greek,
  arabic,
  devanagari,
  cjk,
  hangul,
  hiragana,
  katakana,
  thai,
}

/// Detects unexpected script (writing system) switches in text by measuring
/// Unicode character-class ratios.
///
/// If the fraction of alphabetic characters in [expectedScripts] falls below
/// [threshold], the text is flagged. Useful for catching output-language
/// surprises or cross-script prompt injection.
class LanguageScanner implements Scanner {
  final GuardAction action;

  /// Scripts expected in the text. Default: Latin only.
  final Set<UnicodeScript> expectedScripts;

  /// Minimum fraction of classified chars that must be in [expectedScripts].
  /// Default 0.7 — allows up to 30% unexpected script (names, loanwords).
  final double threshold;

  LanguageScanner({
    this.action = GuardAction.block,
    this.expectedScripts = const {UnicodeScript.latin},
    this.threshold = 0.7,
  });

  @override
  String get name => 'language';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final counts = <UnicodeScript, int>{};
    var classified = 0;

    for (final rune in text.runes) {
      final script = _classify(rune);
      if (script != null) {
        counts[script] = (counts[script] ?? 0) + 1;
        classified += 1;
      }
    }

    if (classified < 10) return ScanResult.pass(name, text);

    var expectedCount = 0;
    for (final s in expectedScripts) {
      expectedCount += counts[s] ?? 0;
    }
    final ratio = expectedCount / classified;
    if (ratio >= threshold) return ScanResult.pass(name, text);

    final unexpected = counts.entries
        .where((e) => !expectedScripts.contains(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final findings = unexpected
        .take(3)
        .map((e) => Finding(
              type: 'language.unexpected_script',
              match: e.key.name,
              confidence: e.value / classified,
            ))
        .toList();

    final passed = action == GuardAction.warn;
    final pct = (ratio * 100).toStringAsFixed(0);
    final tPct = (threshold * 100).toStringAsFixed(0);
    return ScanResult(
      scanner: name,
      passed: passed,
      text: text,
      score: 1.0 - ratio,
      findings: findings,
      reason: '$pct% expected script (threshold $tPct%)',
    );
  }

  static UnicodeScript? _classify(int rune) {
    if ((rune >= 0x0041 && rune <= 0x024F) ||
        (rune >= 0x1E00 && rune <= 0x1EFF)) {
      return UnicodeScript.latin;
    }
    if (rune >= 0x0400 && rune <= 0x04FF) return UnicodeScript.cyrillic;
    if (rune >= 0x0370 && rune <= 0x03FF) return UnicodeScript.greek;
    if (rune >= 0x0600 && rune <= 0x06FF) return UnicodeScript.arabic;
    if (rune >= 0x0900 && rune <= 0x097F) return UnicodeScript.devanagari;
    if (rune >= 0x4E00 && rune <= 0x9FFF) return UnicodeScript.cjk;
    if (rune >= 0xAC00 && rune <= 0xD7AF) return UnicodeScript.hangul;
    if (rune >= 0x3040 && rune <= 0x309F) return UnicodeScript.hiragana;
    if (rune >= 0x30A0 && rune <= 0x30FF) return UnicodeScript.katakana;
    if (rune >= 0x0E00 && rune <= 0x0E7F) return UnicodeScript.thai;
    return null;
  }
}
