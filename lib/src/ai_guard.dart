import 'guard_log.dart';
import 'guard_metrics.dart';
import 'policy.dart';
import 'scanner.dart';
import 'scanner_registry.dart';

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
  final List<ScannerBase> inputScanners;

  /// Scanners applied to model output, in order.
  final List<ScannerBase> outputScanners;

  /// When a scanner throws, treat it as a block (`true`) or skip it (`false`).
  final bool failClosed;

  /// Optional LLM callback for semantic scanners ([LlmDependent]).
  /// Only required when the chain contains [LlmDependent] scanners.
  final LlmCallback? llmCallback;

  /// Post-scan policy rules evaluated after all scanners complete.
  /// A matching rule can escalate warnings to blocks.
  final List<PolicyRule> rules;

  /// Called after every [run] with a structured audit log entry.
  /// Wire to any logging backend. The log contains text hashes, never raw text.
  final void Function(GuardLog log)? onScan;

  /// Called after every [run] with latency and finding-count metrics.
  final void Function(GuardMetrics metrics)? onMetrics;

  AiGuard({
    this.inputScanners = const [],
    this.outputScanners = const [],
    this.failClosed = true,
    this.llmCallback,
    this.rules = const [],
    this.onScan,
    this.onMetrics,
  }) {
    _injectLlmCallback(inputScanners);
    _injectLlmCallback(outputScanners);
  }

  /// Build an [AiGuard] from a JSON-compatible config map.
  ///
  /// The map declares scanner chains, thresholds, and actions without code.
  /// Users who want YAML parse it themselves and pass the resulting `Map`.
  ///
  /// ```json
  /// {
  ///   "failClosed": true,
  ///   "inputScanners": [
  ///     {"type": "pii", "action": "redact", "locales": ["us", "india"]},
  ///     {"type": "secret"},
  ///     {"type": "prompt_injection", "threshold": 0.5}
  ///   ],
  ///   "outputScanners": [
  ///     {"type": "repetition", "threshold": 0.3},
  ///     {"type": "schema", "schema": {"type": "object", "required": ["answer"]}}
  ///   ]
  /// }
  /// ```
  factory AiGuard.fromConfig(
    Map<String, dynamic> config, {
    ScannerRegistry? registry,
    LlmCallback? llmCallback,
    void Function(GuardLog)? onScan,
    void Function(GuardMetrics)? onMetrics,
  }) {
    final reg = registry ?? ScannerRegistry.instance;
    final input = (config['inputScanners'] as List?)
            ?.map((e) => _buildScanner(e, reg))
            .toList() ??
        [];
    final output = (config['outputScanners'] as List?)
            ?.map((e) => _buildScanner(e, reg))
            .toList() ??
        [];
    final rules = (config['rules'] as List?)
            ?.map((e) => PolicyRule.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return AiGuard(
      inputScanners: input,
      outputScanners: output,
      failClosed: config['failClosed'] as bool? ?? true,
      llmCallback: llmCallback,
      rules: rules,
      onScan: onScan,
      onMetrics: onMetrics,
    );
  }

  void _injectLlmCallback(List<ScannerBase> scanners) {
    for (final s in scanners) {
      if (s is LlmDependent) {
        if (llmCallback == null) {
          throw ArgumentError(
            '${s.name} requires llmCallback but none was provided',
          );
        }
        (s as LlmDependent).llmCallback = llmCallback!;
      }
    }
  }

  /// Run [scanners] over [text] for [stage], chaining redactions and stopping
  /// at the first scanner that blocks.
  Future<StageRun> _runStage(
      List<ScannerBase> scanners, String text, ScanStage stage) async {
    final results = <ScanResult>[];
    final mergedMap = <String, String>{};
    var current = text;
    for (final s in scanners) {
      if (!s.stages.contains(stage)) continue;
      ScanResult r;
      try {
        r = s is AsyncScanner
            ? await s.scanAsync(current, stage: stage)
            : (s as Scanner).scan(current, stage: stage);
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
      if (!r.passed) return StageRun(current, results, r, mergedMap);
    }

    // Evaluate policy rules against accumulated findings.
    for (final rule in rules) {
      final action = rule.evaluate(results);
      if (action == GuardAction.block) {
        final blocker = ScanResult(
          scanner: 'policy_rule',
          passed: false,
          text: current,
          score: 1.0,
          reason: 'policy rule triggered: '
              '${rule.condition.aggregate}(${rule.condition.pattern}) '
              '${rule.condition.operator} ${rule.condition.value}',
        );
        results.add(blocker);
        return StageRun(current, results, blocker, mergedMap);
      }
    }
    return StageRun(current, results, null, mergedMap);
  }

  /// Scan input only, returning per-scanner results.
  Future<List<ScanResult>> scanInput(String text) async =>
      (await _runStage(inputScanners, text, ScanStage.input)).results;

  /// Scan output only, returning per-scanner results.
  Future<List<ScanResult>> scanOutput(String text) async =>
      (await _runStage(outputScanners, text, ScanStage.output)).results;

  /// Run input scanners, returning the full stage result including redaction map.
  /// Used by [StreamingAiGuard] to access the redaction map before streaming.
  Future<StageRun> runInputStage(String text) async =>
      _runStage(inputScanners, text, ScanStage.input);

  /// Run output scanners on a single segment.
  /// Used by [StreamingAiGuard] to scan each chunk.
  Future<StageRun> runOutputStage(String text) async =>
      _runStage(outputScanners, text, ScanStage.output);

  /// Scan retrieved chunks before prompt assembly.
  ///
  /// Each chunk is scanned independently through [inputScanners]. Blocked
  /// chunks are dropped; clean chunks are returned (possibly redacted).
  /// Use [RetrievalResult.accepted] for the filtered list and
  /// [RetrievalResult.dropped] to log why chunks were removed.
  Future<RetrievalResult> runRetrievalStage(List<String> chunks) async {
    final results = <ChunkResult>[];
    for (var i = 0; i < chunks.length; i++) {
      final run = await _runStage(inputScanners, chunks[i], ScanStage.input);
      results.add(ChunkResult(
        index: i,
        originalChunk: chunks[i],
        processedChunk: run.text,
        passed: run.blocker == null,
        results: run.results,
        dropReason: run.blocker?.reason,
      ));
    }
    return RetrievalResult(results);
  }

  /// Full guarded round-trip: sanitise input, call the LLM, sanitise output.
  ///
  /// The LLM is never called if an input scanner blocks. When input scanners
  /// redact PII, the output is automatically rehydrated — placeholders in the
  /// LLM response are replaced with the original values.
  ///
  /// If [onScan] or [onMetrics] are set, they fire after the outcome is built.
  Future<GuardOutcome> run({
    required String input,
    required Future<String> Function(String sanitizedInput) llmCall,
  }) async {
    final wallStart = Stopwatch()..start();
    final inputStart = Stopwatch()..start();
    final inRun = await _runStage(inputScanners, input, ScanStage.input);
    inputStart.stop();

    if (inRun.blocker != null) {
      wallStart.stop();
      final outcome = GuardOutcome(
        blocked: true,
        blockedStage: ScanStage.input,
        blockReason: inRun.blocker!.reason,
        piiMap: inRun.redactionMap,
        inputResults: inRun.results,
      );
      _emitCallbacks(
        outcome,
        input,
        null,
        wallStart,
        inputStart,
        Duration.zero,
      );
      return outcome;
    }

    final raw = await llmCall(inRun.text);

    final outputStart = Stopwatch()..start();
    final outRun = await _runStage(outputScanners, raw, ScanStage.output);
    outputStart.stop();

    if (outRun.blocker != null) {
      wallStart.stop();
      final outcome = GuardOutcome(
        blocked: true,
        blockedStage: ScanStage.output,
        blockReason: outRun.blocker!.reason,
        input: inRun.text,
        piiMap: inRun.redactionMap,
        inputResults: inRun.results,
        outputResults: outRun.results,
      );
      _emitCallbacks(
        outcome,
        input,
        raw,
        wallStart,
        inputStart,
        outputStart.elapsed,
      );
      return outcome;
    }

    var rehydrated = outRun.text;
    for (final entry in inRun.redactionMap.entries) {
      rehydrated = rehydrated.replaceAll(entry.key, entry.value);
    }

    wallStart.stop();
    final outcome = GuardOutcome(
      blocked: false,
      input: inRun.text,
      output: rehydrated,
      rawOutput: outRun.text,
      piiMap: inRun.redactionMap,
      inputResults: inRun.results,
      outputResults: outRun.results,
    );
    _emitCallbacks(
      outcome,
      input,
      rehydrated,
      wallStart,
      inputStart,
      outputStart.elapsed,
    );
    return outcome;
  }

  void _emitCallbacks(
    GuardOutcome outcome,
    String inputText,
    String? outputText,
    Stopwatch wall,
    Stopwatch inputSw,
    Duration outputDuration,
  ) {
    if (onScan != null) {
      onScan!(GuardLog.fromOutcome(
        blocked: outcome.blocked,
        blockedStage: outcome.blockedStage,
        blockReason: outcome.blockReason,
        inputText: inputText,
        outputText: outputText,
        inputResults: outcome.inputResults,
        outputResults: outcome.outputResults,
      ));
    }
    if (onMetrics != null) {
      final scannerMetrics = <ScannerMetrics>[
        for (final r in outcome.inputResults)
          ScannerMetrics(
            name: r.scanner,
            stage: ScanStage.input,
            passed: r.passed,
            findingCount: r.findings.length,
          ),
        for (final r in outcome.outputResults)
          ScannerMetrics(
            name: r.scanner,
            stage: ScanStage.output,
            passed: r.passed,
            findingCount: r.findings.length,
          ),
      ];
      onMetrics!(GuardMetrics(
        totalDuration: wall.elapsed,
        inputDuration: inputSw.elapsed,
        outputDuration: outputDuration,
        blocked: outcome.blocked,
        totalFindings: outcome.allFindings.length,
        scanners: scannerMetrics,
      ));
    }
  }

  /// Build a scanner from either a name string or an inline config map,
  /// resolving through the [ScannerRegistry].
  static ScannerBase _buildScanner(dynamic item, ScannerRegistry registry) {
    if (item is String) return registry.build(item);
    final cfg = item as Map<String, dynamic>;
    final type = cfg['type'] as String? ?? cfg['name'] as String?;
    if (type == null) {
      throw ArgumentError('Scanner config must have a "type" or "name" key');
    }
    return registry.build(type, cfg);
  }
}

class StageRun {
  final String text;
  final List<ScanResult> results;
  final ScanResult? blocker;
  final Map<String, String> redactionMap;
  StageRun(this.text, this.results, this.blocker, this.redactionMap);
}

/// Scan outcome for a single retrieved chunk.
class ChunkResult {
  /// Zero-based position in the original list.
  final int index;

  /// The chunk as it was passed in.
  final String originalChunk;

  /// The chunk after any redaction/hashing by the scanner chain.
  final String processedChunk;

  /// `true` when no scanner blocked this chunk.
  final bool passed;

  /// Per-scanner results for this chunk.
  final List<ScanResult> results;

  /// The blocking scanner's reason, or `null` when [passed] is `true`.
  final String? dropReason;

  const ChunkResult({
    required this.index,
    required this.originalChunk,
    required this.processedChunk,
    required this.passed,
    this.results = const [],
    this.dropReason,
  });
}

/// Outcome of [AiGuard.runRetrievalStage].
class RetrievalResult {
  /// Per-chunk scan outcomes, in the same order as the input list.
  final List<ChunkResult> chunks;

  const RetrievalResult(this.chunks);

  /// Processed text of chunks that passed all scanners.
  List<String> get accepted => [
        for (final c in chunks)
          if (c.passed) c.processedChunk
      ];

  /// Chunk results that were blocked by at least one scanner.
  List<ChunkResult> get dropped => [
        for (final c in chunks)
          if (!c.passed) c
      ];

  /// All findings across every chunk.
  List<Finding> get allFindings => [
        for (final c in chunks)
          for (final r in c.results) ...r.findings,
      ];
}
