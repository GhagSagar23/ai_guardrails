import 'package:ai_guardrails/ai_guardrails.dart';

/// Detects profanity using a simple keyword list.
///
/// This is an intentionally simple scanner to demonstrate the plugin pattern.
/// A production profanity scanner would use ML or a comprehensive word list.
class ProfanityScanner extends Scanner {
  /// The action to take on detection.
  final GuardAction action;

  /// Words to flag.
  final Set<String> _words;

  /// Creates a [ProfanityScanner] with the given [words] to detect.
  ProfanityScanner({
    Set<String>? words,
    this.action = GuardAction.block,
  }) : _words = words ?? const {'damn', 'hell', 'crap'};

  @override
  String get name => 'profanity';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final lower = text.toLowerCase();
    final findings = <Finding>[];
    for (final word in _words) {
      var idx = lower.indexOf(word);
      while (idx >= 0) {
        findings.add(Finding(
          type: 'profanity.$word',
          start: idx,
          end: idx + word.length,
          match: text.substring(idx, idx + word.length),
        ));
        idx = lower.indexOf(word, idx + 1);
      }
    }
    if (findings.isEmpty) return ScanResult.pass(name, text);
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text,
          findings: findings, reason: 'Profanity detected');
    }
    return ScanResult.block(name, text,
        findings: findings, reason: 'Profanity detected');
  }
}
