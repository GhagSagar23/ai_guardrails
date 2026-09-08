import '../scanner.dart';

/// Tone register for [PolitenessScanner].
enum ToneRegister { formal, neutral, casual }

/// Detects tone/register mismatches in generated text.
///
/// Configurable target register. Heuristic-based: contractions and slang
/// indicate casual; formal markers indicate formal. Fires when the detected
/// register doesn't match [targetRegister].
class PolitenessScanner implements Scanner {
  final ToneRegister targetRegister;
  final GuardAction action;

  PolitenessScanner({
    required this.targetRegister,
    this.action = GuardAction.warn,
  });

  @override
  String get name => 'politeness';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  static final _casualMarkers = RegExp(
    r"\b(gonna|wanna|gotta|kinda|sorta|ain't|y'all|dude|bro|nah|yeah|lol|omg|btw|imo|tbh|ngl|fwiw|smh|bruh|sus|lit|vibe|slay|fam)\b",
    caseSensitive: false,
  );

  // ponytail: contractions are casual signal, not formal
  static final _contractionPattern = RegExp(
    r"\b\w+'(?:t|re|ve|ll|d|s|m)\b",
    caseSensitive: false,
  );

  static final _formalMarkers = RegExp(
    r'\b(furthermore|henceforth|notwithstanding|pursuant|hereby|aforementioned|therein|whereas|hereinafter|thus|moreover|consequently|accordingly|nevertheless|nonetheless)\b',
    caseSensitive: false,
  );

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final casualCount = _casualMarkers.allMatches(text).length +
        _contractionPattern.allMatches(text).length;
    final formalCount = _formalMarkers.allMatches(text).length;

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words == 0) return ScanResult.pass(name, text);

    final casualRatio = casualCount / words;
    final formalRatio = formalCount / words;

    final detected = _detect(casualRatio, formalRatio);

    if (detected == targetRegister) return ScanResult.pass(name, text);

    final finding = Finding(
      type: 'politeness.${detected.name}',
      match: 'detected ${detected.name}, expected ${targetRegister.name}',
    );
    final reason =
        'tone mismatch: detected ${detected.name}, target ${targetRegister.name}';
    if (action == GuardAction.block) {
      return ScanResult.block(name, text, findings: [finding], reason: reason);
    }
    return ScanResult.warn(name, text, findings: [finding], reason: reason);
  }

  ToneRegister _detect(double casualRatio, double formalRatio) {
    // ponytail: simple threshold, upgrade to ML if heuristic isn't enough
    if (casualRatio > 0.05) return ToneRegister.casual;
    if (formalRatio > 0.03) return ToneRegister.formal;
    return ToneRegister.neutral;
  }
}
