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

  /// The output with redacted PII rehydrated back to original values.
  /// `null` when blocked.
  final String? output;

  /// The raw LLM output before PII rehydration. `null` when blocked.
  /// Same as [output] when no rehydration occurred.
  final String? rawOutput;

  /// Placeholder → original value for every PII span redacted from input.
  /// Empty when no redaction occurred.
  final Map<String, String> piiMap;

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
    this.rawOutput,
    this.piiMap = const {},
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
    final mergedMap = <String, String>{};
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
      mergedMap.addAll(r.redactionMap);
      current = r.text;
      if (!r.passed) return _StageRun(current, results, r, mergedMap);
    }
    return _StageRun(current, results, null, mergedMap);
  }

  /// Scan input only, returning per-scanner results.
  List<ScanResult> scanInput(String text) =>
      _runStage(inputScanners, text, ScanStage.input).results;

  /// Scan output only, returning per-scanner results.
  List<ScanResult> scanOutput(String text) =>
      _runStage(outputScanners, text, ScanStage.output).results;

  /// Full guarded round-trip: sanitise input, call the LLM, sanitise output.
  ///
  /// The LLM is never called if an input scanner blocks. When input scanners
  /// redact PII, the output is automatically rehydrated — placeholders in the
  /// LLM response are replaced with the original values.
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
        piiMap: inRun.redactionMap,
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
        piiMap: inRun.redactionMap,
        inputResults: inRun.results,
        outputResults: outRun.results,
      );
    }

    // Rehydrate: replace input-redaction placeholders in the output.
    var rehydrated = outRun.text;
    for (final entry in inRun.redactionMap.entries) {
      rehydrated = rehydrated.replaceAll(entry.key, entry.value);
    }

    return GuardOutcome(
      blocked: false,
      input: inRun.text,
      output: rehydrated,
      rawOutput: outRun.text,
      piiMap: inRun.redactionMap,
      inputResults: inRun.results,
      outputResults: outRun.results,
    );
  }
}

class _StageRun {
  final String text;
  final List<ScanResult> results;
  final ScanResult? blocker;
  final Map<String, String> redactionMap;
  _StageRun(this.text, this.results, this.blocker, this.redactionMap);
}
