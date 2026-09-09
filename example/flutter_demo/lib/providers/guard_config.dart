import 'package:ai_guardrails/ai_guardrails.dart';

/// Pre-configured [AiGuard] instances for the demo app's Chat and RAG tabs.
class GuardConfig {
  /// Chat tab: full input sanitisation + output quality checks.
  static AiGuard chatGuard() => AiGuard(
        inputScanners: [
          PiiScanner(action: GuardAction.redact),
          SecretScanner(),
          PromptInjectionScanner(threshold: 0.5),
          InvisibleTextScanner(),
        ],
        outputScanners: [
          CompetitorMentionScanner(
            ['Acme', 'Globex'],
            action: GuardAction.warn,
          ),
          ReadingLevelScanner(maxGrade: 12, action: GuardAction.warn),
          PolitenessScanner(
            targetRegister: ToneRegister.neutral,
            action: GuardAction.warn,
          ),
        ],
        onFailActions: {
          'pii': OnFailAction.warn,
          'prompt_injection': OnFailAction.block,
          'secret': OnFailAction.block,
          'competitor_mention': OnFailAction.warn,
        },
      );

  /// RAG tab: input sanitisation + grounding check on output.
  ///
  /// [context] is the joined accepted chunks for the grounding scanner.
  static AiGuard ragGuard({String context = ''}) => AiGuard(
        inputScanners: [
          PiiScanner(action: GuardAction.redact),
          PromptInjectionScanner(threshold: 0.5),
        ],
        outputScanners: [
          GroundingScanner(
            context: context,
            threshold: 0.3,
            action: GuardAction.warn,
          ),
          ReadingLevelScanner(maxGrade: 14, action: GuardAction.warn),
        ],
        onFailActions: {
          'pii': OnFailAction.warn,
          'prompt_injection': OnFailAction.block,
        },
      );

  /// Retrieval stage: scans raw chunks for injection and tool-output attacks.
  static AiGuard retrievalGuard() => AiGuard(
        inputScanners: [
          PromptInjectionScanner(threshold: 0.7),
          ToolOutputScanner(action: GuardAction.block),
        ],
      );
}
