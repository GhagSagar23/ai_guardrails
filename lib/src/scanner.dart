/// Core scanner contract for `ai_guardrails`.
///
/// Everything in this file is the frozen public API that every concrete
/// scanner builds against. Keep it small and stable.
library;

/// Where in the LLM round-trip a scanner runs.
enum ScanStage { input, output }

/// What happens to text when a scanner detects a violation.
///
/// * [block]  — reject the whole request/response (`passed == false`).
/// * [redact] — replace matched spans with a placeholder and continue.
/// * [hash]   — replace matched spans with a stable one-way token.
/// * [warn]   — record findings but let the text pass through unchanged.
enum GuardAction { block, redact, hash, warn }

/// A single detected issue inside a scanned string.
class Finding {
  /// Dotted type, e.g. `pii.email`, `secret.aws_key`, `injection.override`.
  final String type;

  /// Char offsets into the scanned text; both `-1` when not span-based.
  final int start;
  final int end;

  /// The matched substring. Omitted (`null`) when echoing it would leak data.
  final String? match;

  /// Detector confidence, `0.0`..`1.0`.
  final double confidence;

  const Finding({
    required this.type,
    this.start = -1,
    this.end = -1,
    this.match,
    this.confidence = 1.0,
  });

  @override
  String toString() => 'Finding($type @$start..$end conf=$confidence)';
}

/// Outcome of running one [Scanner] over one string.
class ScanResult {
  /// The [Scanner.name] that produced this result.
  final String scanner;

  /// `true` when the text is safe to proceed with.
  final bool passed;

  /// Severity, `0.0` (clean) .. `1.0` (maximal violation).
  final double score;

  /// The text after any redaction/hashing; equal to the input when unchanged.
  final String text;

  /// Everything the scanner matched.
  final List<Finding> findings;

  /// Human-readable explanation when [passed] is `false` or text was changed.
  final String? reason;

  /// Placeholder → original value for every span this scanner redacted or
  /// hashed. Empty when nothing was transformed. Used by [AiGuard] to
  /// rehydrate PII in LLM output.
  final Map<String, String> redactionMap;

  const ScanResult({
    required this.scanner,
    required this.passed,
    required this.text,
    this.score = 0.0,
    this.findings = const [],
    this.reason,
    this.redactionMap = const {},
  });

  /// A clean pass with no findings.
  const ScanResult.pass(this.scanner, this.text)
      : passed = true,
        score = 0.0,
        findings = const [],
        reason = null,
        redactionMap = const {};

  bool get hasFindings => findings.isNotEmpty;

  @override
  String toString() =>
      'ScanResult($scanner passed=$passed score=$score findings=${findings.length})';
}

/// A composable safety check over a single string.
///
/// Implementations MUST be pure and synchronous: no I/O, no network, no
/// mutable shared state. That keeps the pipeline deterministic and cheap
/// enough to run on the UI isolate.
abstract class Scanner {
  /// Stable, unique name (also used in [ScanResult.scanner]).
  String get name;

  /// Stages this scanner is allowed to run in.
  Set<ScanStage> get stages;

  /// Scan [text] for the given [stage] and return a result.
  ScanResult scan(String text, {ScanStage stage = ScanStage.input});
}
