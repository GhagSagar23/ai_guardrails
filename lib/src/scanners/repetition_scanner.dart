import '../scanner.dart';

/// Detects degenerate model output by measuring word-level n-gram repetition.
///
/// A high repetition ratio (many duplicate n-grams relative to total) signals
/// the model is looping. Runs on output only by default.
class RepetitionScanner implements Scanner {
  /// N-gram size in words. Default 3 (trigrams).
  final int ngramSize;

  /// Repetition ratio threshold (0.0–1.0). Ratio = 1 − (unique / total).
  /// Default 0.3 — text where >30% of n-gram slots are duplicates is flagged.
  final double threshold;

  /// What to do when repetition exceeds [threshold].
  final GuardAction action;

  RepetitionScanner({
    this.ngramSize = 3,
    this.threshold = 0.3,
    this.action = GuardAction.block,
  });

  @override
  String get name => 'repetition';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final words = text.split(RegExp(r'\s+'));
    final totalPositions = words.length - ngramSize + 1;
    if (totalPositions < 2) return ScanResult.pass(name, text);

    final counts = <String, int>{};
    for (var i = 0; i < totalPositions; i++) {
      final gram = words.sublist(i, i + ngramSize).join(' ');
      counts[gram] = (counts[gram] ?? 0) + 1;
    }

    final unique = counts.length;
    final score = 1.0 - (unique / totalPositions);
    if (score < threshold) return ScanResult.pass(name, text);

    final repeated = counts.entries
        .where((e) => e.value > 1)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final findings = repeated
        .take(5)
        .map((e) => Finding(
              type: 'repetition.ngram',
              match: e.key,
              confidence: e.value / totalPositions,
            ))
        .toList();

    final passed = action == GuardAction.warn;
    return ScanResult(
      scanner: name,
      passed: passed,
      text: text,
      score: score,
      findings: findings,
      reason:
          '${(score * 100).toStringAsFixed(0)}% repetition (threshold ${(threshold * 100).toStringAsFixed(0)}%)',
    );
  }
}
