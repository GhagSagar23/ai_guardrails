import 'ai_guard.dart';
import 'on_fail_action.dart';

/// Wraps [AiGuard] with automatic corrective retry when output scanners
/// trigger [OnFailAction.reask].
///
/// On each failed attempt, injects a feedback prompt describing what went
/// wrong and retries the LLM call with the amended input. Stops after
/// [maxReasks] retries or when the output passes all scanners.
///
/// ```dart
/// final guarded = GuardedLlmCall(
///   guard: myGuard,
///   maxReasks: 2,
/// );
/// final outcome = await guarded.call(
///   input: 'Summarise this document',
///   llmCall: (prompt) => myLlm.generate(prompt),
/// );
/// ```
class GuardedLlmCall {
  final AiGuard guard;

  /// Maximum number of retry attempts when [OnFailAction.reask] fires.
  final int maxReasks;

  /// Builds the retry prompt from the original input and the failed outcome.
  /// When `null`, [defaultRetryPrompt] is used.
  final String Function(String original, GuardOutcome failed)?
      retryPromptBuilder;

  GuardedLlmCall({
    required this.guard,
    this.maxReasks = 3,
    this.retryPromptBuilder,
  }) : assert(maxReasks >= 0);

  /// Run the guarded LLM call with automatic retries on [OnFailAction.reask].
  ///
  /// Returns the first passing [GuardOutcome], or the last failed one when
  /// [maxReasks] is exhausted. Non-reask failures (block, refrain, etc.)
  /// return immediately without retrying.
  Future<GuardOutcome> call({
    required String input,
    required Future<String> Function(String sanitizedInput) llmCall,
  }) async {
    var currentInput = input;

    for (var attempt = 0; attempt <= maxReasks; attempt++) {
      final outcome = await guard.run(
        input: currentInput,
        llmCall: llmCall,
      );

      if (!outcome.blocked && outcome.failAction != OnFailAction.reask) {
        return outcome;
      }

      if (outcome.failAction != OnFailAction.reask) return outcome;
      if (attempt == maxReasks) return outcome;

      currentInput = retryPromptBuilder?.call(input, outcome) ??
          defaultRetryPrompt(input, outcome);
    }

    // Unreachable, but satisfies the analyser.
    return guard.run(input: currentInput, llmCall: llmCall);
  }

  /// Default retry prompt: appends a system note describing the rejection.
  static String defaultRetryPrompt(String original, GuardOutcome outcome) {
    final types = outcome.allFindings.map((f) => f.type).toSet().join(', ');
    final reason = outcome.blockReason ?? types;
    return '$original\n\n'
        '[System: Your previous response was rejected. '
        'Reason: $reason. '
        'Please try again while avoiding these issues.]';
  }
}
