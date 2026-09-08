/// Core scanner contract for `ai_guardrails`.
///
/// Everything in this file is the frozen public API that every concrete
/// scanner builds against. Keep it small and stable.
library;

/// Signature for a caller-provided LLM call.
///
/// The package never imports an LLM SDK — this callback is the abstraction
/// boundary. Semantic scanners ([LlmDependent]) use it for judgment prompts;
/// the caller controls routing, model, and credentials.
typedef LlmCallback = Future<String> Function(String prompt);

/// Where in the LLM round-trip a scanner runs.
enum ScanStage { input, output }

/// What happens to text when a scanner detects a violation.
///
/// * [block]  — reject the whole request/response (`passed == false`).
/// * [redact] — replace matched spans with a placeholder and continue.
/// * [hash]   — replace matched spans with a stable one-way token.
/// * [warn]   — record findings but let the text pass through unchanged.
enum GuardAction { block, redact, hash, warn, transform }

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

  /// Original span → replacement for permanent content rewrites.
  ///
  /// Unlike [redactionMap] (which is reversed in output), transformations
  /// are permanent — the orchestrator records them for audit but does not
  /// undo them. Populated by scanners using [GuardAction.transform].
  final Map<String, String> transformations;

  const ScanResult({
    required this.scanner,
    required this.passed,
    required this.text,
    this.score = 0.0,
    this.findings = const [],
    this.reason,
    this.redactionMap = const {},
    this.transformations = const {},
  });

  /// A clean pass with no findings.
  const ScanResult.pass(this.scanner, this.text)
      : passed = true,
        score = 0.0,
        findings = const [],
        reason = null,
        redactionMap = const {},
        transformations = const {};

  /// A blocking result.
  const ScanResult.block(
    this.scanner,
    this.text, {
    required this.findings,
    this.reason,
    this.score = 1.0,
  })  : passed = false,
        redactionMap = const {},
        transformations = const {};

  /// A non-blocking result that records findings.
  const ScanResult.warn(
    this.scanner,
    this.text, {
    required this.findings,
    this.reason,
    this.score = 0.5,
  })  : passed = true,
        redactionMap = const {},
        transformations = const {};

  /// A passing result where the scanner rewrote content.
  ///
  /// The scanner modifies [text] and records what it changed in
  /// [transformations] (original → replacement). Unlike redaction,
  /// transforms are permanent — not reversed in output.
  const ScanResult.transform(
    this.scanner,
    this.text, {
    required this.findings,
    this.transformations = const {},
    this.reason,
    this.score = 0.5,
  })  : passed = true,
        redactionMap = const {};

  bool get hasFindings => findings.isNotEmpty;

  @override
  String toString() =>
      'ScanResult($scanner passed=$passed score=$score findings=${findings.length})';
}

/// Base type for composable scanner contracts.
///
/// Sealed to [Scanner] and [AsyncScanner] (same library) — prevents third
/// parties from implementing [ScannerBase] directly, which would bypass the
/// `is AsyncScanner` / `as Scanner` dispatch in `AiGuard._runStage` and
/// either silently no-op (failClosed: false) or block with a misleading
/// "type cast" error (failClosed: true).
sealed class ScannerBase {
  String get name;
  Set<ScanStage> get stages;
}

/// A composable safety check over a single string.
///
/// Implementations MUST be pure and synchronous: no I/O, no network, no
/// mutable shared state. That keeps the pipeline deterministic and cheap
/// enough to run on the UI isolate.
abstract class Scanner implements ScannerBase {
  /// Stable, unique name (also used in [ScanResult.scanner]).
  @override
  String get name;

  /// Stages this scanner is allowed to run in.
  @override
  Set<ScanStage> get stages;

  /// Scan [text] for the given [stage] and return a result.
  ScanResult scan(String text, {ScanStage stage = ScanStage.input});
}

/// Async counterpart of [Scanner] for scanners that need I/O or model
/// inference (e.g. on-device ML classifiers).
///
/// Implementations may perform I/O, load models, or run compute-heavy
/// inference. [AiGuard] awaits async scanners inline in the pipeline.
abstract class AsyncScanner implements ScannerBase {
  @override
  String get name;

  @override
  Set<ScanStage> get stages;

  /// Scan [text] for the given [stage] and return a result.
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input});
}

/// Mixin for scanners that require an [LlmCallback].
///
/// [AiGuard] injects the callback at construction time. Scanners that mix
/// this in can call [llmCallback] during scanning to get LLM judgments.
mixin LlmDependent {
  LlmCallback? _llmCallback;

  LlmCallback get llmCallback {
    if (_llmCallback == null) {
      throw StateError(
        'llmCallback not injected — pass llmCallback to AiGuard constructor',
      );
    }
    return _llmCallback!;
  }

  set llmCallback(LlmCallback cb) => _llmCallback = cb;
}
