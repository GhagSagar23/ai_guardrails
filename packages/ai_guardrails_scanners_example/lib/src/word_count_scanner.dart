import 'package:ai_guardrails/ai_guardrails.dart';

/// Blocks text that exceeds a maximum word count.
///
/// Another simple scanner to demonstrate multi-scanner plugins.
class WordCountScanner extends Scanner {
  /// Maximum allowed words.
  final int maxWords;

  /// The action to take on detection.
  final GuardAction action;

  /// Creates a [WordCountScanner].
  WordCountScanner({this.maxWords = 500, this.action = GuardAction.block});

  @override
  String get name => 'word_count';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final count = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (count <= maxWords) return ScanResult.pass(name, text);
    final findings = [
      Finding(type: 'word_count.exceeded', confidence: count / maxWords)
    ];
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text,
          findings: findings,
          reason: '$count words exceeds limit of $maxWords');
    }
    return ScanResult.block(name, text,
        findings: findings, reason: '$count words exceeds limit of $maxWords');
  }
}
