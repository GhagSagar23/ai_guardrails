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

  /// 4-state customer support flow for the Flow tab demo.
  static ConversationFlow supportFlow() => ConversationFlow(
        name: 'support',
        initialState: 'greeting',
        states: {
          'greeting': FlowState(
            name: 'greeting',
            transitions: [
              FlowTransition(intent: 'billing', targetState: 'billing'),
              FlowTransition(intent: 'support', targetState: 'support'),
            ],
          ),
          'billing': FlowState(
            name: 'billing',
            allowedTopics: {
              'bill',
              'invoice',
              'payment',
              'charge',
              'subscription',
              'plan',
              'price',
              'cost',
              'refund',
              'money',
              'pay',
              'upgrade',
            },
            transitions: [
              FlowTransition(intent: 'support', targetState: 'support'),
              FlowTransition(intent: 'goodbye', targetState: 'farewell'),
            ],
          ),
          'support': FlowState(
            name: 'support',
            allowedTopics: {
              'bug',
              'error',
              'issue',
              'problem',
              'help',
              'fix',
              'broken',
              'crash',
              'feature',
              'work',
              'slow',
              'down',
            },
            transitions: [
              FlowTransition(intent: 'billing', targetState: 'billing'),
              FlowTransition(intent: 'goodbye', targetState: 'farewell'),
            ],
          ),
          'farewell': FlowState(
            name: 'farewell',
            terminal: true,
          ),
        },
        canonicalForms: [
          CanonicalForm(
            intent: 'billing',
            keywords: {
              'bill',
              'billing',
              'invoice',
              'payment',
              'charge',
              'subscription',
              'plan',
              'price',
              'cost',
            },
          ),
          CanonicalForm(
            intent: 'support',
            keywords: {
              'bug',
              'error',
              'issue',
              'problem',
              'fix',
              'broken',
              'crash',
              'support',
            },
          ),
          CanonicalForm(
            intent: 'goodbye',
            keywords: {'bye', 'goodbye', 'thank', 'thanks', 'done', 'exit'},
          ),
        ],
      );

  /// Flow tab: wraps [GuardSession] + [ConversationFlow].
  static FlowGuardSession flowSession() => FlowGuardSession(
        session: GuardSession(
          guard: AiGuard(
            inputScanners: [
              PiiScanner(action: GuardAction.redact),
              PromptInjectionScanner(threshold: 0.5),
            ],
            onFailActions: {
              'pii': OnFailAction.warn,
              'prompt_injection': OnFailAction.block,
            },
          ),
        ),
        flow: supportFlow(),
      );

  /// Session tab: [GuardSession] with [EscalationPolicy] for escalation demo.
  static GuardSession escalationSession({
    void Function(EscalationLevel, EscalationLevel)? onEscalation,
  }) =>
      GuardSession(
        guard: AiGuard(
          inputScanners: [
            PiiScanner(action: GuardAction.redact),
            PromptInjectionScanner(threshold: 0.5),
            InvisibleTextScanner(),
          ],
          outputScanners: [
            CompetitorMentionScanner(
              ['Acme', 'Globex'],
              action: GuardAction.warn,
            ),
          ],
          onFailActions: {
            'pii': OnFailAction.warn,
            'prompt_injection': OnFailAction.warn,
          },
        ),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 3,
          terminateThreshold: 5,
        ),
        onEscalation: onEscalation,
      );
}
