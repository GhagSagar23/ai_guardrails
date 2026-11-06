import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:langchain_core/chains.dart';

/// A LangChain [BaseChain] that wraps input/output scanning around an
/// inner chain or model call.
///
/// ```dart
/// final chain = GuardrailsChain(guard: myGuard, innerChain: llmChain);
/// final result = await chain.call({'input': userPrompt});
/// ```
class GuardrailsChain extends BaseChain {
  /// The [AiGuard] pipeline to run.
  final AiGuard guard;

  /// The inner chain whose output is scanned.
  final BaseChain innerChain;

  /// When `true`, a blocked scan throws [GuardrailsBlockedException].
  /// When `false`, returns the outcome with `blocked: true` in the output.
  final bool throwOnBlock;

  /// Creates a [GuardrailsChain].
  GuardrailsChain({
    required this.guard,
    required this.innerChain,
    this.throwOnBlock = true,
  });

  @override
  String get chainType => 'guardrails';

  @override
  Set<String> get inputKeys => innerChain.inputKeys;

  @override
  Set<String> get outputKeys => {
        ...innerChain.outputKeys,
        'guardrails_input_results',
        'guardrails_output_results',
        'guardrails_blocked',
        'guardrails_redaction_map',
      };

  @override
  Future<ChainValues> callInternal(ChainValues inputs) async {
    final inputKey = innerChain.inputKeys.firstOrNull ?? 'input';
    final raw = inputs[inputKey]?.toString() ?? '';

    final inputRun = await guard.runInputStage(raw);
    if (inputRun.blocker != null) {
      if (throwOnBlock) {
        throw GuardrailsBlockedException(
          stage: 'input',
          reason: inputRun.blocker!.reason ?? 'Input blocked',
          results: inputRun.results,
        );
      }
      return {
        ...innerChain.outputKeys.fold<ChainValues>({}, (m, k) => m..[k] = ''),
        'guardrails_blocked': true,
        'guardrails_input_results': inputRun.results,
        'guardrails_output_results': <ScanResult>[],
        'guardrails_redaction_map': inputRun.redactionMap,
      };
    }

    final sanitised = {...inputs, inputKey: inputRun.text};
    final innerOutput =
        await innerChain.call(sanitised, returnOnlyOutputs: true);

    final outputKey = innerChain.outputKeys.firstOrNull ?? 'output';
    final outputText = innerOutput[outputKey]?.toString() ?? '';

    final outputRun = await guard.runOutputStage(outputText);
    if (outputRun.blocker != null) {
      if (throwOnBlock) {
        throw GuardrailsBlockedException(
          stage: 'output',
          reason: outputRun.blocker!.reason ?? 'Output blocked',
          results: outputRun.results,
        );
      }
      return {
        ...innerOutput,
        'guardrails_blocked': true,
        'guardrails_input_results': inputRun.results,
        'guardrails_output_results': outputRun.results,
        'guardrails_redaction_map': inputRun.redactionMap,
      };
    }

    var finalText = outputRun.text;
    for (final entry in inputRun.redactionMap.entries) {
      finalText = finalText.replaceAll(entry.key, entry.value);
    }

    return {
      ...innerOutput,
      outputKey: finalText,
      'guardrails_blocked': false,
      'guardrails_input_results': inputRun.results,
      'guardrails_output_results': outputRun.results,
      'guardrails_redaction_map': inputRun.redactionMap,
    };
  }
}

/// Thrown when a guardrails scan blocks content.
class GuardrailsBlockedException implements Exception {
  /// Which stage blocked: `'input'` or `'output'`.
  final String stage;

  /// Human-readable block reason.
  final String reason;

  /// The scan results that caused the block.
  final List<ScanResult> results;

  /// Creates a [GuardrailsBlockedException].
  const GuardrailsBlockedException({
    required this.stage,
    required this.reason,
    required this.results,
  });

  @override
  String toString() => 'GuardrailsBlockedException($stage): $reason';
}
