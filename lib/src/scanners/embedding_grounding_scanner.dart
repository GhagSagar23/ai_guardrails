import 'dart:math' as math;

import '../scanner.dart';

/// Semantic grounding scanner using embedding cosine similarity.
///
/// Upgrades the keyword-overlap [GroundingScanner] with vector similarity.
/// The [EmbeddingCallback] is injected via [EmbeddingDependent] by [AiGuard].
///
/// Optionally accepts an [nliCallback] for NLI-style entailment rescue
/// when embedding similarity falls below [threshold].
///
/// Output-stage only.
class EmbeddingGroundingScanner extends AsyncScanner with EmbeddingDependent {
  final List<String> sourceChunks;

  /// Minimum cosine similarity to consider output grounded. Default 0.7.
  final double threshold;

  final GuardAction action;

  /// Optional LLM callback for NLI entailment checks. When provided,
  /// chunks that fail embedding similarity get a second chance via NLI.
  final LlmCallback? nliCallback;

  List<List<double>>? _cachedSourceEmbeddings;

  EmbeddingGroundingScanner({
    required this.sourceChunks,
    this.threshold = 0.7,
    this.action = GuardAction.warn,
    this.nliCallback,
  });

  @override
  String get name => 'embedding_grounding';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    if (text.trim().isEmpty || sourceChunks.isEmpty) {
      return ScanResult.pass(name, text);
    }

    _cachedSourceEmbeddings ??= await Future.wait(
      sourceChunks.map((c) => embeddingCallback(c)),
    );

    final outputEmb = await embeddingCallback(text);

    var maxSim = -1.0;
    for (var i = 0; i < _cachedSourceEmbeddings!.length; i++) {
      final sim = cosineSimilarity(outputEmb, _cachedSourceEmbeddings![i]);
      if (sim > maxSim) maxSim = sim;
    }

    if (maxSim >= threshold) return ScanResult.pass(name, text);

    // NLI rescue: if embedding failed but NLI callback available
    if (nliCallback != null) {
      for (final chunk in sourceChunks) {
        if (await _nliCheck(text, chunk)) return ScanResult.pass(name, text);
      }
    }

    final pct = (maxSim * 100).toStringAsFixed(0);
    final tPct = (threshold * 100).toStringAsFixed(0);
    final reason = 'embedding similarity $pct% (threshold $tPct%)';
    final score = (1.0 - maxSim).clamp(0.0, 1.0);
    final findings = [
      Finding(type: 'grounding.low_similarity', confidence: score),
    ];

    return action == GuardAction.warn
        ? ScanResult.warn(name, text,
            score: score, findings: findings, reason: reason)
        : ScanResult.block(name, text,
            score: score, findings: findings, reason: reason);
  }

  Future<bool> _nliCheck(String output, String context) async {
    final prompt = StringBuffer()
      ..writeln('You are an entailment checker.')
      ..writeln('Context: $context')
      ..writeln('Claim: $output')
      ..writeln()
      ..writeln('Does the claim follow from the context?')
      ..writeln('Respond with exactly ENTAILED or NOT_ENTAILED.');

    final result = await nliCallback!(prompt.toString());
    final upper = result.trim().toUpperCase();
    return upper.startsWith('ENTAILED') && !upper.startsWith('NOT_ENTAILED');
  }

  /// Cosine similarity between two equal-length vectors.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
