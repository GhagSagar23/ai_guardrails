import '../data/language_profiles.dart';
import '../scanner.dart';

// ponytail: trigram frequency profiles; upgrade to fastText-lid model when dart:ffi packaging matures

/// Detects the natural language of text using trigram frequency analysis.
///
/// Compares character trigram distributions against known language profiles
/// and blocks (or warns) when the detected language is not in [allow].
/// For non-Latin scripts (CJK, Devanagari, Cyrillic, Hangul),
/// Unicode range detection is used instead of trigrams.
///
/// Complements [LanguageScanner] (script-ratio detector) by distinguishing
/// languages that share a script, e.g. English vs Spanish vs French.
///
/// ```dart
/// final scanner = LanguageDetectionScanner(allow: {'en', 'es'});
/// final r = scanner.scan('Bonjour le monde');
/// // findings: language_detection.detected = 'fr', not in allow set → block
/// ```
class LanguageDetectionScanner implements Scanner {
  /// ISO 639-1 codes of allowed languages.
  final Set<String> allow;

  /// Minimum confidence to report a detection. Below this the result is
  /// `'unknown'` and the scan passes. The weighted-overlap algorithm produces
  /// scores in the 0.15–0.45 range for typical sentences — set this lower
  /// than you would for an ML classifier.
  final double minConfidence;

  /// The action taken when the detected language is not allowed.
  final GuardAction action;

  /// Creates a [LanguageDetectionScanner].
  LanguageDetectionScanner({
    required this.allow,
    this.minConfidence = 0.1,
    this.action = GuardAction.block,
  }) : assert(allow.isNotEmpty, 'allow set must not be empty');

  @override
  String get name => 'language_detection';

  @override
  Set<ScanStage> get stages => const {ScanStage.input};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    if (text.length < 10) return ScanResult.pass(name, text);

    final scriptLang = _detectByScript(text);
    if (scriptLang != null) {
      if (allow.contains(scriptLang)) return ScanResult.pass(name, text);
      return _blocked(text, scriptLang, 0.95);
    }

    final result = _detectByTrigram(text);
    if (result == null || result.confidence < minConfidence) {
      return ScanResult.pass(name, text);
    }

    if (allow.contains(result.lang)) return ScanResult.pass(name, text);
    return _blocked(text, result.lang, result.confidence);
  }

  ScanResult _blocked(String text, String lang, double confidence) {
    final findings = [
      Finding(
        type: 'language_detection.detected',
        match: lang,
        confidence: confidence,
      ),
    ];
    final reason = 'Detected language "$lang" not in allowed set $allow';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text,
          score: confidence, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text,
        score: confidence, findings: findings, reason: reason);
  }

  /// Detect non-Latin-script languages by Unicode character ranges.
  /// Returns null if the text is predominantly Latin.
  static String? _detectByScript(String text) {
    var cjk = 0;
    var hangul = 0;
    var hiragana = 0;
    var katakana = 0;
    var devanagari = 0;
    var cyrillic = 0;
    var latin = 0;
    var total = 0;

    for (final rune in text.runes) {
      if (rune < 0x20) continue;
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        cjk++;
      } else if (rune >= 0xAC00 && rune <= 0xD7AF) {
        hangul++;
      } else if (rune >= 0x3040 && rune <= 0x309F) {
        hiragana++;
      } else if (rune >= 0x30A0 && rune <= 0x30FF) {
        katakana++;
      } else if (rune >= 0x0900 && rune <= 0x097F) {
        devanagari++;
      } else if (rune >= 0x0400 && rune <= 0x04FF) {
        cyrillic++;
      } else if ((rune >= 0x0041 && rune <= 0x024F) ||
          (rune >= 0x1E00 && rune <= 0x1EFF)) {
        latin++;
      } else {
        continue;
      }
      total++;
    }

    if (total < 5) return null;
    final thresh = total * 0.3;

    if (hiragana + katakana > thresh) return 'ja';
    if (hangul > thresh) return 'ko';
    if (cjk > thresh && hiragana + katakana == 0) return 'zh';
    if (devanagari > thresh) return 'hi';
    if (cyrillic > thresh) return 'ru';
    if (latin > thresh) return null; // fall through to trigram
    return null;
  }

  /// Detect Latin-script language by weighted profile overlap.
  ///
  /// For each language profile, sums the profile weight of every trigram that
  /// also appears in the text, normalised by the sum of all profile weights.
  /// The highest-scoring language wins. Score range 0.0–1.0.
  static _Detection? _detectByTrigram(String text) {
    final lower = text.toLowerCase();
    final textTrigrams = <String>{};
    for (var i = 0; i < lower.length - 2; i++) {
      textTrigrams.add(lower.substring(i, i + 3));
    }

    if (textTrigrams.isEmpty) return null;

    String? bestLang;
    var bestScore = -1.0;

    for (final entry in languageProfiles.entries) {
      final lang = entry.key;
      final profile = entry.value;

      var matched = 0.0;
      var total = 0.0;
      for (final tri in profile.keys) {
        final w = profile[tri]!;
        total += w;
        if (textTrigrams.contains(tri)) matched += w;
      }

      final score = total == 0 ? 0.0 : matched / total;
      if (score > bestScore) {
        bestScore = score;
        bestLang = lang;
      }
    }

    if (bestLang == null) return null;
    return _Detection(bestLang, bestScore.clamp(0.0, 1.0));
  }
}

class _Detection {
  final String lang;
  final double confidence;
  const _Detection(this.lang, this.confidence);
}
