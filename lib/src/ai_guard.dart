import 'scanner.dart';

/// The result of a full guarded round-trip.
class GuardOutcome {
  /// `true` when an input or output scanner blocked the request.
  final bool blocked;

  /// The stage at which blocking happened, or `null` when not blocked.
  final ScanStage? blockedStage;

  /// Why it was blocked (the first blocking scanner's reason).
  final String? blockReason;

  /// The (possibly redacted) input actually passed to the LLM.
  /// `null` when blocked before the LLM ran.
  final String? input;

  /// The (possibly redacted) output. `null` when blocked.
  final String? output;

  /// Per-scanner results for the input pipeline.
  final List<ScanResult> inputResults;

  /// Per-scanner results for the output pipeline.
  final List<ScanResult> outputResults;

  const GuardOutcome({
    required this.blocked,
    this.blockedStage,
    this.blockReason,
    this.input,
    this.output,
    this.inputResults = const [],
    this.outputResults = const [],
  });

  /// Every finding raised across both pipelines.
  List<Finding> get allFindings => [
        for (final r in inputResults) ...r.findings,
        for (final r in outputResults) ...r.findings,
      ];
}

/// Orchestrates input and output scanner pipelines around an LLM call.
///
/// Redacting scanners chain: each scanner sees the previous scanner's
/// transformed text, and the fully-sanitised string is what reaches
/// [run]'s `llmCall`.
class AiGuard {
  /// Scanners applied to user input, in order.
  final List<Scanner> inputScanners;

  /// Scanners applied to model output, in order.
  final List<Scanner> outputScanners;

  /// When a scanner throws, treat it as a block (`true`) or skip it (`false`).
  final bool failClosed;

  AiGuard({
    this.inputScanners = const [],
    this.outputScanners = const [],
    this.failClosed = true,
  });

  /// Run [scanners] over [text] for [stage], chaining redactions and stopping
  /// at the first scanner that blocks.
  _StageRun _runStage(List<Scanner> scanners, String text, ScanStage stage) {
    final results = <ScanResult>[];
    var current = text;
    for (final s in scanners) {
      if (!s.stages.contains(stage)) continue;
      ScanResult r;
      try {
        r = s.scan(current, stage: stage);
      } catch (e) {
        if (!failClosed) continue;
        r = ScanResult(
          scanner: s.name,
          passed: false,
          text: current,
          score: 1.0,
          reason: 'scanner error: $e',
        );
      }
      results.add(r);
      current = r.text;
      if (!r.passed) return _StageRun(current, results, r);
    }
    return _StageRun(current, results, null);
  }

  /// Scan input only, returning per-scanner results.
  List<ScanResult> scanInput(String text) =>
      _runStage(inputScanners, text, ScanStage.input).results;

  /// Scan output only, returning per-scanner results.
  List<ScanResult> scanOutput(String text) =>
      _runStage(outputScanners, text, ScanStage.output).results;

  /// Full guarded round-trip: sanitise input, call the LLM, sanitise output.
  ///
  /// The LLM is never called if an input scanner blocks.
  Future<GuardOutcome> run({
    required String input,
    required Future<String> Function(String sanitizedInput) llmCall,
  }) async {
    final inRun = _runStage(inputScanners, input, ScanStage.input);
    if (inRun.blocker != null) {
      return GuardOutcome(
        blocked: true,
        blockedStage: ScanStage.input,
        blockReason: inRun.blocker!.reason,
        inputResults: inRun.results,
      );
    }

    final raw = await llmCall(inRun.text);

    final outRun = _runStage(outputScanners, raw, ScanStage.output);
    if (outRun.blocker != null) {
      return GuardOutcome(
        blocked: true,
        blockedStage: ScanStage.output,
        blockReason: outRun.blocker!.reason,
        input: inRun.text,
        inputResults: inRun.results,
        outputResults: outRun.results,
      );
    }

    return GuardOutcome(
      blocked: false,
      input: inRun.text,
      output: outRun.text,
      inputResults: inRun.results,
      outputResults: outRun.results,
    );
  }
}

class _StageRun {
  final String text;
  final List<ScanResult> results;
  final ScanResult? blocker;
  _StageRun(this.text, this.results, this.blocker);
}
