/// Abstract tracer for OpenTelemetry-compatible instrumentation.
///
/// The package provides instrumentation points; the caller bridges to
/// their OTel SDK. Zero cost when not configured — [AiGuard] null-checks
/// the tracer and skips all instrumentation.
///
/// ```dart
/// class MyOtelTracer implements GuardTracer {
///   final otel.Tracer _tracer;
///   MyOtelTracer(this._tracer);
///
///   @override
///   GuardSpan startSpan(String name, {Map<String, Object>? attributes}) {
///     final span = _tracer.startSpan(name);
///     attributes?.forEach(span.setAttribute);
///     return MyOtelSpan(span);
///   }
/// }
/// ```
abstract class GuardTracer {
  /// Start a new root span.
  GuardSpan startSpan(String name, {Map<String, Object>? attributes});
}

/// A single span in a trace tree.
///
/// Operations on an ended span should be silently ignored — callers
/// need not guard against double-end.
abstract class GuardSpan {
  /// Add or update an attribute.
  void setAttribute(String key, Object value);

  /// Start a child span nested under this one.
  GuardSpan startChild(String name, {Map<String, Object>? attributes});

  /// Record an error event.
  void recordError(Object error, {StackTrace? stackTrace});

  /// Mark this span as complete.
  void end();
}

/// OTel semantic convention attribute keys for guardrail operations.
///
/// Use these as span attribute keys for consistent, queryable telemetry.
///
/// ```dart
/// span.setAttribute(GuardSemantics.scannerName, 'pii');
/// span.setAttribute(GuardSemantics.scanResult, 'block');
/// ```
class GuardSemantics {
  GuardSemantics._();

  /// Scanner name (e.g. `pii`, `secret`, `prompt_injection`).
  static const scannerName = 'guardrail.scanner.name';

  /// Scan stage: `input` or `output`.
  static const scanStage = 'guardrail.scan.stage';

  /// Scan result: `pass`, `warn`, or `block`.
  static const scanResult = 'guardrail.scan.result';

  /// Number of findings in a scan result.
  static const findingCount = 'guardrail.findings.count';

  /// Comma-separated finding type strings.
  static const findingTypes = 'guardrail.findings.types';

  /// Whether the pipeline was blocked.
  static const blocked = 'guardrail.blocked';

  /// Human-readable block reason.
  static const blockReason = 'guardrail.block_reason';

  /// Duration in milliseconds.
  static const durationMs = 'guardrail.duration_ms';

  /// Error type string on scanner failure.
  static const errorType = 'guardrail.error.type';

  /// Streaming segment index.
  static const segmentIndex = 'guardrail.segment.index';

  /// Retrieval chunk index.
  static const chunkIndex = 'guardrail.chunk.index';

  /// Tool name for tool-output scanning.
  static const toolName = 'guardrail.tool.name';
}
