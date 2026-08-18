import 'scanner.dart';

/// Metrics snapshot emitted after every [AiGuard.run] call via [AiGuard.onMetrics].
class GuardMetrics {
  /// Total wall-clock time for the full guarded round-trip (including LLM call).
  final Duration totalDuration;

  /// Time spent in input scanners only.
  final Duration inputDuration;

  /// Time spent in output scanners only (zero if blocked at input).
  final Duration outputDuration;

  /// Whether the request was blocked.
  final bool blocked;

  /// Total findings across both pipelines.
  final int totalFindings;

  /// Per-scanner metrics.
  final List<ScannerMetrics> scanners;

  const GuardMetrics({
    required this.totalDuration,
    required this.inputDuration,
    required this.outputDuration,
    required this.blocked,
    required this.totalFindings,
    required this.scanners,
  });
}

/// Per-scanner metrics within a [GuardMetrics] snapshot.
class ScannerMetrics {
  final String name;
  final ScanStage stage;
  final bool passed;
  final int findingCount;

  const ScannerMetrics({
    required this.name,
    required this.stage,
    required this.passed,
    required this.findingCount,
  });
}
