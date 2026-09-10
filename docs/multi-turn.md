# Multi-turn sessions

Back to [README](../README.md).

---

`GuardSession` wraps `AiGuard` with mutable state — turn counting, finding
accumulation, and optional escalation policies. Scanners stay stateless.

```dart
final session = GuardSession(
  guard: AiGuard(
    inputScanners: [SecretScanner(action: GuardAction.warn)],
  ),
  escalationPolicy: const EscalationPolicy(
    blockThreshold: 3,   // warn → block after 3 total findings
    terminateThreshold: 5, // block → terminate after 5
  ),
);

for (final userMsg in conversation) {
  final outcome = await session.run(input: userMsg, llmCall: myLlm);

  print('turn ${session.turnCount}, level: ${session.escalationLevel}');
  print('findings so far: ${session.findingCounts}');

  if (outcome.blocked) break;
}

session.reset(); // reuse for next conversation
```

## Escalation levels

| Level | Behaviour |
| --- | --- |
| **warn** (default) | findings pass through as-is |
| **block** | turns with any findings are force-blocked, clean turns still pass |
| **terminate** | all `run()` calls immediately return blocked |

Without an `escalationPolicy`, `GuardSession` is just `AiGuard` with turn
counting and finding accumulation — no behavioral change.

See [`example/guard_session_example.dart`](../example/guard_session_example.dart)
for a runnable multi-turn example with escalation.
