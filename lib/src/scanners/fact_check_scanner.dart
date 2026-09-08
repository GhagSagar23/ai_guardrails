import '../scanner.dart';

/// NLI-style fact-checker: asks the caller's LLM whether the output follows
/// from a provided source [context].
///
/// Returns one of three verdicts:
/// - **supported** — output follows from context (pass)
/// - **contradicted** — output contradicts context (finding)
/// - **unsupported** — output makes claims not in context (finding)
///
/// Complements [GroundingScanner] (keyword-overlap heuristic) with semantic
/// judgment. Create a new instance per context.
class FactCheckScanner extends AsyncScanner with LlmDependent {
  final String context;
  final GuardAction action;

  FactCheckScanner({
    required this.context,
    this.action = GuardAction.warn,
  });

  @override
  String get name => 'fact_check';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    if (text.trim().isEmpty) return ScanResult.pass(name, text);

    final prompt = StringBuffer()
      ..writeln('You are a factual verification system. Determine whether '
          'the output is supported by the provided context.')
      ..writeln()
      ..writeln('Context:')
      ..writeln(context)
      ..writeln()
      ..writeln('Output:')
      ..writeln(text)
      ..writeln()
      ..writeln('Respond with exactly one word on the first line:')
      ..writeln('SUPPORTED — the output follows from the context')
      ..writeln('CONTRADICTED — the output contradicts the context')
      ..writeln('UNSUPPORTED — the output makes claims not in the context')
      ..writeln()
      ..writeln('Then briefly explain your reasoning.');

    final verdict = await llmCallback(prompt.toString());
    final firstLine = verdict.trim().split('\n').first.trim().toUpperCase();

    if (firstLine.startsWith('SUPPORTED')) {
      return ScanResult.pass(name, text);
    }

    final contradicted = firstLine.startsWith('CONTRADICTED');
    final type =
        contradicted ? 'factcheck.contradiction' : 'factcheck.unsupported';
    final reason = contradicted
        ? 'Output contradicts the provided context'
        : 'Output contains claims not in the provided context';
    final score = contradicted ? 1.0 : 0.7;

    final explanation = _parseExplanation(verdict);
    final findings = [
      Finding(type: type, match: explanation, confidence: score),
    ];

    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text,
          score: score, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text,
        score: score, findings: findings, reason: reason);
  }

  static String? _parseExplanation(String verdict) {
    final lines = verdict.trim().split('\n');
    if (lines.length < 2) return null;
    return lines
        .skip(1)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join(' ');
  }
}
