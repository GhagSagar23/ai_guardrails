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

/// In-memory tracer for debugging and testing.
///
/// Records all spans in [spans]. Use [clear] to reset between tests.
class InMemoryTracer implements GuardTracer {
  /// Root spans, in start order.
  final spans = <InMemorySpan>[];

  @override
  GuardSpan startSpan(String name, {Map<String, Object>? attributes}) {
    final span = InMemorySpan(name, attributes: attributes);
    spans.add(span);
    return span;
  }

  /// Remove all recorded spans.
  void clear() => spans.clear();

  /// All spans flattened (root + children), depth-first.
  List<InMemorySpan> get allSpans {
    final result = <InMemorySpan>[];
    void walk(InMemorySpan s) {
      result.add(s);
      s.children.forEach(walk);
    }

    spans.forEach(walk);
    return result;
  }

  /// Find all spans matching [name].
  List<InMemorySpan> findByName(String name) =>
      allSpans.where((s) => s.name == name).toList();
}

/// In-memory span for debugging and testing.
class InMemorySpan implements GuardSpan {
  /// Span name.
  final String name;

  /// Attributes set at start or via [setAttribute].
  final Map<String, Object> attributes;

  /// Child spans, in start order.
  final List<InMemorySpan> children = [];

  /// Errors passed to [recordError].
  final List<Object> errors = [];

  /// Whether [end] has been called.
  bool ended = false;

  /// Creates a span named [name] with optional initial [attributes].
  InMemorySpan(this.name, {Map<String, Object>? attributes})
      : attributes = {...?attributes};

  @override
  void setAttribute(String key, Object value) => attributes[key] = value;

  @override
  GuardSpan startChild(String name, {Map<String, Object>? attributes}) {
    final child = InMemorySpan(name, attributes: attributes);
    children.add(child);
    return child;
  }

  @override
  void recordError(Object error, {StackTrace? stackTrace}) => errors.add(error);

  @override
  void end() => ended = true;

  @override
  String toString() => 'InMemorySpan($name, ended=$ended, '
      'children=${children.length}, attrs=$attributes)';
}
