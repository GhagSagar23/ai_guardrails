import '../scanner.dart';

/// Blocks input that exceeds an approximate token budget.
///
/// Tokens are estimated with a cheap word+punctuation-run tokenizer — good
/// enough for a guardrail, not a real BPE count. Only [GuardAction.block] and
/// [GuardAction.warn] are meaningful; [GuardAction.redact] and
/// [GuardAction.hash] are treated as [GuardAction.warn] (there is nothing to
/// redact — the whole text is the problem).
class TokenLimitScanner implements Scanner {
  /// Maximum allowed estimated tokens.
  final int maxTokens;

  /// Block on overflow, or merely warn.
  final GuardAction action;

  TokenLimitScanner({this.maxTokens = 4096, this.action = GuardAction.block});

  static final RegExp _token = RegExp(r'\w+|[^\w\s]+');

  @override
  String get name => 'token_limit';

  @override
  Set<ScanStage> get stages => const {ScanStage.input};

  /// Approximate token count: runs of word chars and runs of punctuation.
  int estimateTokens(String text) => _token.allMatches(text).length;

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final count = estimateTokens(text);
    if (count <= maxTokens) return ScanResult.pass(name, text);

    final finding = const Finding(type: 'token_limit.exceeded');
    final reason = 'token limit exceeded: ~$count tokens > $maxTokens';

    if (action == GuardAction.block) {
      return ScanResult(
        scanner: name,
        passed: false,
        text: text,
        score: 1.0,
        findings: [finding],
        reason: reason,
      );
    }
    // warn (and redact/hash treated as warn)
    return ScanResult(
      scanner: name,
      passed: true,
      text: text,
      score: 0.5,
      findings: [finding],
      reason: reason,
    );
  }
}
