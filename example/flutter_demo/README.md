# flutter_demo

Flutter demo for [`ai_guardrails`](../../README.md), a pure-Dart LLM safety
scanner package. It shows input/output guarding in four realistic flows. The
package is resolved by path (`path: ../..`), so the demo always runs against
the local source.

## Run

```bash
cd example/flutter_demo
flutter pub get
flutter run            # pick a device: macOS, Chrome, Android, iOS...
flutter analyze        # static checks
flutter test           # widget + config tests
```

On desktop the Chat tab calls the `claude -p` CLI if installed; on every other
platform (or without the CLI) it uses a built-in mock LLM, so no API key is
needed. The translate icon in the app bar switches the language of the guard
messages (10 locales).

## Screens

| Tab | What it shows |
| --- | --- |
| Chat | Guarded chat via `GuardedLlmCall`: PII redaction badge, blocked-request banner, expandable "Guard Log" of output findings. Filter chips above the chat toggle the optional scanners below. |
| RAG | Retrieval pipeline: chunks are scanned for injection / tool-output attacks (`retrievalGuard`), accepted chunks form the context, and the answer is checked for grounding. |
| Flow | `ConversationFlow` state machine (greeting -> billing / support -> farewell) wrapped in a `GuardSession`, with off-topic detection per state. |
| Session | `GuardSession` + `EscalationPolicy`: repeated findings escalate warn -> block -> terminate; reset restores the session. |

## Scanners demonstrated

Always on (Chat): `PiiScanner` (redact), `SecretScanner`,
`PromptInjectionScanner`, `InvisibleTextScanner`, `CompetitorMentionScanner`,
`ReadingLevelScanner`, `PolitenessScanner`.

Toggleable in the Chat tab (off by default):

- `ToxicityScanner` - multi-category toxicity on input and output (blocks).
- `RelevanceScanner` - checks the reply is relevant to your prompt (warns).
- `LanguageDetectionScanner` - trigram language detection; only en/es/fr/de
  input is allowed (blocks others, e.g. Japanese).

Other tabs: `GroundingScanner`, `ToolOutputScanner`, `ConversationFlow`,
`GuardSession` / `EscalationPolicy`.

Scanner wiring lives in `lib/providers/guard_config.dart`.
