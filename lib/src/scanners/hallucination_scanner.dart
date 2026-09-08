import '../scanner.dart';

/// SelfCheckGPT-style hallucination detector.
///
/// Generates [sampleCount] alternative completions for [prompt] via
/// [LlmCallback], then asks the LLM to cross-check consistency between the
/// original output and the samples. Inconsistent claims are flagged as
/// likely hallucinations.
///
/// Create a new instance per request (the [prompt] changes each turn).
/// Output-stage only.
class HallucinationScanner extends AsyncScanner with LlmDependent {
  final String prompt;
  final int sampleCount;
  final GuardAction action;

  HallucinationScanner({
    required this.prompt,
    this.sampleCount = 3,
    this.action = GuardAction.warn,
  }) : assert(sampleCount > 0);

  @override
  String get name => 'hallucination';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    if (text.trim().isEmpty) return ScanResult.pass(name, text);

    final samples = await Future.wait(
      List.generate(sampleCount, (_) => llmCallback(prompt)),
    );

    final judge = StringBuffer()
      ..writeln('You are a hallucination detector. Compare the original '
          'response with alternative responses generated for the same question.')
      ..writeln()
      ..writeln('Original response:')
      ..writeln(text)
      ..writeln();
    for (var i = 0; i < samples.length; i++) {
      judge
        ..writeln('Alternative response ${i + 1}:')
        ..writeln(samples[i])
        ..writeln();
    }
    judge
      ..writeln('Identify claims in the original that are NOT consistent '
          'with the alternatives.')
      ..writeln()
      ..writeln(
          'If all claims are consistent, respond with exactly: CONSISTENT')
      ..writeln('If there are inconsistent claims, respond with: INCONSISTENT')
      ..writeln(
          'Then list each inconsistent claim on a new line prefixed with "- ".');

    final verdict = await llmCallback(judge.toString());
    final upper = verdict.trim().toUpperCase();

    if (upper.startsWith('CONSISTENT') && !upper.startsWith('INCONSISTENT')) {
      return ScanResult.pass(name, text);
    }

    final claims = _parseClaims(verdict);
    final findings = claims.isEmpty
        ? [const Finding(type: 'hallucination.inconsistent_claim')]
        : claims
            .map((c) => Finding(
                  type: 'hallucination.inconsistent_claim',
                  match: c,
                ))
            .toList();

    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text,
          findings: findings, reason: 'Inconsistent claims detected');
    }
    return ScanResult.block(name, text,
        findings: findings, reason: 'Inconsistent claims detected');
  }

  static List<String> _parseClaims(String verdict) {
    final lines = verdict.split('\n');
    return lines
        .map((l) => l.trim())
        .where((l) => l.startsWith('- ') || l.startsWith('* '))
        .map((l) => l.substring(2).trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }
}
