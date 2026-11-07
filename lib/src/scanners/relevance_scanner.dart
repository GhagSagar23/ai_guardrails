import '../data/stop_words.dart';
import '../scanner.dart';

final _tokenRe = RegExp(r'[\p{L}\p{N}]+(?:\x27\p{L}+)?', unicode: true);

final _refusalRe = RegExp(
  r'\b(?:i\s+cannot|i\s+can\x27t|i\s+can\s+not|i\s+am\s+unable|i\x27m\s+unable|'
  r'i\s+won\x27t\s+be\s+able|i\x27m\s+sorry|i\s+am\s+sorry|i\s+apologi[sz]e|'
  r'as\s+an\s+ai)\b',
  caseSensitive: false,
);

/// Checks whether model output is relevant to the user's question.
///
/// Combines Jaccard token overlap, keyword recall of the question's content
/// words, and a length-ratio penalty into a score in `0.0`..`1.0`
/// (`0.4 * jaccard + 0.4 * recall + 0.2 * lengthRatio`). Refusal phrases
/// ("I cannot", "As an AI", ...) force the score to `0.0`.
///
/// Output-stage only. Without a non-empty [referenceText] the scanner passes,
/// since relevance cannot be judged.
// ponytail: token-overlap heuristic; upgrade to embedding cosine similarity via EmbeddingGroundingScanner for production accuracy
class RelevanceScanner implements Scanner {
  /// The original user question the output is compared against.
  ///
  /// Mutable so callers can set it per request before scanning.
  String? referenceText;

  /// Minimum acceptable relevance score; below this a finding is raised.
  final double minRelevance;

  /// The action taken when relevance is too low.
  final GuardAction action;

  /// Creates a [RelevanceScanner].
  RelevanceScanner({
    this.referenceText,
    this.minRelevance = 0.3,
    this.action = GuardAction.warn,
  });

  @override
  String get name => 'relevance';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  static Set<String> _tokens(String text) => {
        for (final m in _tokenRe.allMatches(text.toLowerCase()))
          if (!relevanceStopWords.contains(m.group(0))) m.group(0)!,
      };

  /// Relevance of [output] to [reference], `0.0`..`1.0`.
  ///
  /// Returns `1.0` when [reference] has no content words (nothing to compare).
  double relevanceScore(String output, String reference) {
    if (_refusalRe.hasMatch(output.replaceAll('’', "'"))) return 0.0;
    final inTokens = _tokens(reference);
    if (inTokens.isEmpty) return 1.0;
    final outTokens = _tokens(output);
    final shared = inTokens.intersection(outTokens).length;
    final union = inTokens.union(outTokens).length;
    final jaccard = shared / union;
    final recall = shared / inTokens.length;
    final inLen = reference.trim().length;
    final lengthRatio = (output.trim().length / inLen).clamp(0.0, 1.0);
    return (0.4 * jaccard + 0.4 * recall + 0.2 * lengthRatio).clamp(0.0, 1.0);
  }

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final ref = referenceText;
    if (stage != ScanStage.output || ref == null || ref.trim().isEmpty) {
      return ScanResult.pass(name, text);
    }
    final score = relevanceScore(text, ref);
    if (score >= minRelevance) return ScanResult.pass(name, text);

    final findings = [
      Finding(
        type: 'relevance.low_score',
        match: score.toStringAsFixed(2),
        confidence: 1.0 - score,
      ),
    ];
    final reason = 'relevance score ${score.toStringAsFixed(2)} below '
        'minimum ${minRelevance.toStringAsFixed(2)}';
    if (action == GuardAction.block) {
      return ScanResult.block(name, text, findings: findings, reason: reason);
    }
    return ScanResult.warn(name, text, findings: findings, reason: reason);
  }
}
