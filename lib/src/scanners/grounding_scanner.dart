import '../scanner.dart';

// ponytail: minimal stop words, not exhaustive — covers English function words
const _stopWords = <String>{
  'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of',
  'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
  'should', 'may', 'might', 'shall', 'can', 'it', 'its', 'this', 'that',
  'these', 'those', 'i', 'you', 'he', 'she', 'we', 'they', 'me', 'him',
  'her', 'us', 'them', 'my', 'your', 'his', 'our', 'their', 'not', 'no',
  'if', 'then', 'so', 'as', 'up', 'out', 'about', 'into', 'over', 'after',
  'all', 'also', 'just', 'more', 'some', 'such', 'than', 'too', 'very',
  'each', 'every', 'both', 'few', 'most', 'other', 'any', 'only', 'own',
  'same', 'when', 'where', 'how', 'what', 'which', 'who', 'whom', 'why',
  'there', 'here', 'now', 'once', 'while', 'during', 'before',
  'between', 'through', 'above', 'below', 'again', 'further', 'because',
};

final _wordRe = RegExp(r"[a-zA-Z'À-ɏ]+");

/// Checks whether LLM output is grounded in a provided source [context].
///
/// Extracts content words (non-stop-words) from both context and output,
/// computes the fraction of output words that appear in the context, and
/// flags text when that overlap falls below [threshold].
///
/// This is a heuristic keyword-overlap check, not semantic similarity.
/// Documented accuracy limits: misses paraphrases, catches fabricated entities.
class GroundingScanner implements Scanner {
  /// The reference/source text to check output against.
  final String context;

  /// Minimum fraction of output content words found in context.
  /// Default 0.5 — at least half of the output's content words must appear
  /// somewhere in the context.
  final double threshold;

  final GuardAction action;

  GroundingScanner({
    required this.context,
    this.threshold = 0.5,
    this.action = GuardAction.warn,
  });

  @override
  String get name => 'grounding';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  late final Set<String> _contextWords = _contentWords(context);

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final outputWords = _contentWords(text);
    if (outputWords.length < 3) return ScanResult.pass(name, text);

    final grounded =
        outputWords.where((w) => _contextWords.contains(w)).length;
    final ratio = grounded / outputWords.length;

    if (ratio >= threshold) return ScanResult.pass(name, text);

    final ungrounded = outputWords
        .where((w) => !_contextWords.contains(w))
        .take(10)
        .toList();

    final findings = ungrounded
        .map((w) => Finding(
              type: 'grounding.unsupported_claim',
              match: w,
              confidence: 1.0 - ratio,
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
      reason: '$pct% grounded (threshold $tPct%)',
    );
  }

  static Set<String> _contentWords(String text) {
    final words = <String>{};
    for (final m in _wordRe.allMatches(text)) {
      final w = m[0]!.toLowerCase();
      if (w.length > 1 && !_stopWords.contains(w)) {
        words.add(w);
      }
    }
    return words;
  }
}
