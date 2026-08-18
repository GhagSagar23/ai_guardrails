import 'guard_log.dart';
import 'guard_metrics.dart';
import 'scanner.dart';
import 'scanners/banned_pattern_scanner.dart';
import 'scanners/banned_topic_scanner.dart';
import 'scanners/code_execution_scanner.dart';
import 'scanners/grounding_scanner.dart';
import 'scanners/invisible_text_scanner.dart';
import 'scanners/language_scanner.dart';
import 'data/pii_patterns.dart';
import 'scanners/pii_scanner.dart';
import 'scanners/prompt_injection_scanner.dart';
import 'scanners/repetition_scanner.dart';
import 'scanners/schema_validator.dart';
import 'scanners/secret_scanner.dart';
import 'scanners/token_limit_scanner.dart';
import 'scanners/url_scanner.dart';

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

  /// Called after every [run] with a structured audit log entry.
  /// Wire to any logging backend. The log contains text hashes, never raw text.
  final void Function(GuardLog log)? onScan;

  /// Called after every [run] with latency and finding-count metrics.
  final void Function(GuardMetrics metrics)? onMetrics;

  AiGuard({
    this.inputScanners = const [],
    this.outputScanners = const [],
    this.failClosed = true,
    this.onScan,
    this.onMetrics,
  });

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
    void Function(GuardLog)? onScan,
    void Function(GuardMetrics)? onMetrics,
  }) {
    final input = (config['inputScanners'] as List?)
            ?.map((e) => _buildScanner(e as Map<String, dynamic>))
            .toList() ??
        [];
    final output = (config['outputScanners'] as List?)
            ?.map((e) => _buildScanner(e as Map<String, dynamic>))
            .toList() ??
        [];

    return AiGuard(
      inputScanners: input,
      outputScanners: output,
      failClosed: config['failClosed'] as bool? ?? true,
      onScan: onScan,
      onMetrics: onMetrics,
    );
  }

  /// Run [scanners] over [text] for [stage], chaining redactions and stopping
  /// at the first scanner that blocks.
  StageRun _runStage(List<Scanner> scanners, String text, ScanStage stage) {
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
      if (!r.passed) return StageRun(current, results, r, mergedMap);
    }
    return StageRun(current, results, null, mergedMap);
  }

  /// Scan input only, returning per-scanner results.
  List<ScanResult> scanInput(String text) =>
      _runStage(inputScanners, text, ScanStage.input).results;

  /// Scan output only, returning per-scanner results.
  List<ScanResult> scanOutput(String text) =>
      _runStage(outputScanners, text, ScanStage.output).results;

  /// Run input scanners, returning the full stage result including redaction map.
  /// Used by [StreamingAiGuard] to access the redaction map before streaming.
  StageRun runInputStage(String text) =>
      _runStage(inputScanners, text, ScanStage.input);

  /// Run output scanners on a single segment.
  /// Used by [StreamingAiGuard] to scan each chunk.
  StageRun runOutputStage(String text) =>
      _runStage(outputScanners, text, ScanStage.output);

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
    final inRun = _runStage(inputScanners, input, ScanStage.input);
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
        outcome, input, null, wallStart, inputStart, Duration.zero,
      );
      return outcome;
    }

    final raw = await llmCall(inRun.text);

    final outputStart = Stopwatch()..start();
    final outRun = _runStage(outputScanners, raw, ScanStage.output);
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
        outcome, input, raw, wallStart, inputStart, outputStart.elapsed,
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
      outcome, input, rehydrated, wallStart, inputStart, outputStart.elapsed,
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

  static Scanner _buildScanner(Map<String, dynamic> cfg) {
    final type = cfg['type'] as String;
    final action = _parseAction(cfg['action'] as String?);
    switch (type) {
      case 'pii':
        return PiiScanner(
          action: action ?? GuardAction.redact,
          locales: _parseLocales(cfg['locales']),
          types: (cfg['types'] as List?)?.cast<String>().toSet(),
        );
      case 'secret':
        return SecretScanner(action: action ?? GuardAction.block);
      case 'prompt_injection':
        return PromptInjectionScanner(
          threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.5,
          action: action ?? GuardAction.block,
        );
      case 'invisible_text':
        return InvisibleTextScanner(action: action ?? GuardAction.redact);
      case 'banned_topic':
        return BannedTopicScanner(
          (cfg['topics'] as List).cast<String>(),
          action: action ?? GuardAction.block,
          caseSensitive: cfg['caseSensitive'] as bool? ?? false,
        );
      case 'banned_pattern':
        final patterns = (cfg['patterns'] as List)
            .map((p) => RegExp(p as String))
            .toList();
        return BannedPatternScanner(
          patterns,
          action: action ?? GuardAction.block,
          name: cfg['name'] as String? ?? 'banned_pattern',
        );
      case 'token_limit':
        return TokenLimitScanner(
          maxTokens: cfg['maxTokens'] as int? ?? 4096,
          action: action ?? GuardAction.block,
        );
      case 'repetition':
        return RepetitionScanner(
          threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.3,
          ngramSize: cfg['ngramSize'] as int? ?? 3,
          action: action ?? GuardAction.block,
        );
      case 'url':
        return UrlScanner(action: action ?? GuardAction.block);
      case 'language':
        return LanguageScanner(
          threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.7,
          action: action ?? GuardAction.block,
        );
      case 'code_exec':
        return CodeExecutionScanner(action: action ?? GuardAction.block);
      case 'grounding':
        return GroundingScanner(
          context: cfg['context'] as String? ?? '',
          threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.5,
          action: action ?? GuardAction.warn,
        );
      case 'schema':
        return SchemaValidator(
          cfg['schema'] as Map<String, dynamic>,
          action: action ?? GuardAction.block,
        );
      default:
        throw ArgumentError('Unknown scanner type: $type');
    }
  }

  static GuardAction? _parseAction(String? s) {
    if (s == null) return null;
    switch (s) {
      case 'block':
        return GuardAction.block;
      case 'redact':
        return GuardAction.redact;
      case 'hash':
        return GuardAction.hash;
      case 'warn':
        return GuardAction.warn;
      default:
        throw ArgumentError('Unknown action: $s');
    }
  }

  static Set<PiiLocale> _parseLocales(dynamic v) {
    if (v == null) return PiiLocale.values.toSet();
    return (v as List).map((s) {
      for (final locale in PiiLocale.values) {
        if (locale.name == s) return locale;
      }
      throw ArgumentError('Unknown locale: $s');
    }).toSet();
  }
}

class StageRun {
  final String text;
  final List<ScanResult> results;
  final ScanResult? blocker;
  final Map<String, String> redactionMap;
  StageRun(this.text, this.results, this.blocker, this.redactionMap);
}
