import 'dart:math' show log, max;

import '../scanner.dart';

/// Detects context-exhaustion padding attacks using information-theoretic
/// heuristics.
///
/// Two independent checks:
/// 1. **Shannon entropy floor** — low-entropy text is likely padding designed
///    to exhaust the context window.
/// 2. **Single-char run ratio** — long runs of the same character are a
///    simpler form of the same attack.
///
/// Complements [TokenLimitScanner] (size cap) and [RepetitionScanner]
/// (word-level n-gram degeneration) with character-level analysis.
class PaddingAttackScanner implements Scanner {
  /// Minimum Shannon entropy in bits per character. Text below this
  /// threshold is flagged as potential padding. Default 3.0.
  final double entropyFloor;

  /// Maximum fraction of text that may consist of single-character runs
  /// of [minRunLength] or longer. Default 0.1 (10%).
  final double maxRunRatio;

  /// Minimum consecutive identical characters to count as a "run".
  /// Default 5.
  final int minRunLength;

  final GuardAction action;

  PaddingAttackScanner({
    this.entropyFloor = 3.0,
    this.maxRunRatio = 0.1,
    this.minRunLength = 5,
    this.action = GuardAction.block,
  })  : assert(entropyFloor >= 0),
        assert(maxRunRatio >= 0 && maxRunRatio <= 1),
        assert(minRunLength >= 2);

  @override
  String get name => 'padding_attack';

  @override
  Set<ScanStage> get stages => const {ScanStage.input};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    if (text.length < 20) return ScanResult.pass(name, text);

    final findings = <Finding>[];

    final entropy = _shannonEntropy(text);
    if (entropy < entropyFloor) {
      findings.add(Finding(
        type: 'padding.low_entropy',
        confidence: _entropyConfidence(entropy),
      ));
    }

    final runRatio = _runRatio(text);
    if (runRatio > maxRunRatio) {
      findings.add(Finding(
        type: 'padding.char_run',
        confidence: (runRatio / max(maxRunRatio, 0.01)).clamp(0.0, 1.0),
      ));
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    return action == GuardAction.block
        ? ScanResult.block(name, text,
            findings: findings,
            reason: 'padding attack detected '
                '(entropy=${entropy.toStringAsFixed(2)}, '
                'runRatio=${runRatio.toStringAsFixed(2)})')
        : ScanResult.warn(name, text,
            findings: findings,
            reason: 'possible padding '
                '(entropy=${entropy.toStringAsFixed(2)}, '
                'runRatio=${runRatio.toStringAsFixed(2)})');
  }

  double _shannonEntropy(String text) {
    if (text.isEmpty) return 0.0;
    final freq = <int, int>{};
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      freq[c] = (freq[c] ?? 0) + 1;
    }
    final len = text.length.toDouble();
    var entropy = 0.0;
    for (final count in freq.values) {
      final p = count / len;
      if (p > 0) entropy -= p * (log(p) / log(2));
    }
    return entropy;
  }

  double _entropyConfidence(double entropy) {
    if (entropyFloor <= 0) return 1.0;
    return (1.0 - entropy / entropyFloor).clamp(0.0, 1.0);
  }

  double _runRatio(String text) {
    if (text.isEmpty) return 0.0;
    var runChars = 0;
    var i = 0;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      var runLen = 1;
      while (i + runLen < text.length && text.codeUnitAt(i + runLen) == c) {
        runLen++;
      }
      if (runLen >= minRunLength) runChars += runLen;
      i += runLen;
    }
    return runChars / text.length;
  }
}
