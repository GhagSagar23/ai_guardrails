import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  Future<String> stubLlm(String input) async => 'ok: $input';
  const secret = 'key AKIAIOSFODNN7EXAMPLE';

  group('EscalationRule — per-type thresholds', () {
    test('type rule triggers block before global threshold', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 100,
          terminateThreshold: 200,
          typeRules: {
            'secret.*': EscalationRule(blockThreshold: 1, terminateThreshold: 3),
          },
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.block);
    });

    test('type rule triggers terminate', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 100,
          terminateThreshold: 200,
          typeRules: {
            'secret.*': EscalationRule(blockThreshold: 1, terminateThreshold: 2),
          },
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.terminate);
    });

    test('exact type match works', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 100,
          terminateThreshold: 200,
          typeRules: {
            'secret.aws_access_key': EscalationRule(blockThreshold: 1, terminateThreshold: 3),
          },
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.block);
    });

    test('non-matching type rule does not trigger', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 100,
          terminateThreshold: 200,
          typeRules: {
            'pii.*': EscalationRule(blockThreshold: 1, terminateThreshold: 2),
          },
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.warn);
    });

    test('highest type rule wins across multiple rules', () async {
      final session = GuardSession(
        guard: AiGuard(
          inputScanners: [SecretScanner(action: GuardAction.warn)],
          outputScanners: [CodeExecutionScanner(action: GuardAction.warn)],
        ),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 100,
          terminateThreshold: 200,
          typeRules: {
            'secret.*': EscalationRule(blockThreshold: 1, terminateThreshold: 10),
            'code_exec.*': EscalationRule(blockThreshold: 10, terminateThreshold: 1),
          },
        ),
      );
      await session.run(
        input: secret,
        llmCall: (_) async => 'eval("x")',
      );
      // secret.* fires block (1 finding >= 1), code_exec.* fires terminate (1 >= 1)
      expect(session.escalationLevel, EscalationLevel.terminate);
    });
  });

  group('EscalationPolicy.window — sliding window', () {
    test('window limits which turns count', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 2,
          terminateThreshold: 100,
          window: 2,
        ),
      );
      // Turn 1: finding
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.warn);
      // Turn 2: clean — window now [finding, clean]
      await session.run(input: 'clean', llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.warn);
      // Turn 3: clean — window now [clean, clean], old finding decayed
      await session.run(input: 'clean', llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.warn);
    });

    test('window-based escalation de-escalates', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 2,
          terminateThreshold: 100,
          window: 3,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.block);
      // Clean turns push violations out of window
      await session.run(input: 'clean', llmCall: stubLlm);
      await session.run(input: 'clean', llmCall: stubLlm);
      await session.run(input: 'clean', llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.warn);
    });

    test('terminated session with window recovers after cooldown', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 2,
          window: 3,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.terminate);
      // Terminated runs add empty snapshots; after 3, window is all-empty
      await session.run(input: 'a', llmCall: stubLlm);
      await session.run(input: 'b', llmCall: stubLlm);
      await session.run(input: 'c', llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.warn);
    });

    test('without window, escalation is monotonic', () async {
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 100,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.block);
      // Many clean turns — still block because no window
      for (var i = 0; i < 10; i++) {
        await session.run(input: 'clean', llmCall: stubLlm);
      }
      expect(session.escalationLevel, EscalationLevel.block);
    });
  });

  group('GuardSession.onEscalation callback', () {
    test('fires on escalation level change', () async {
      final transitions = <(EscalationLevel, EscalationLevel)>[];
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 2,
        ),
        onEscalation: (from, to) => transitions.add((from, to)),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(transitions, [(EscalationLevel.warn, EscalationLevel.block)]);
      await session.run(input: secret, llmCall: stubLlm);
      expect(transitions.last, (EscalationLevel.block, EscalationLevel.terminate));
    });

    test('does not fire when level stays the same', () async {
      final transitions = <(EscalationLevel, EscalationLevel)>[];
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 100,
          terminateThreshold: 200,
        ),
        onEscalation: (from, to) => transitions.add((from, to)),
      );
      await session.run(input: 'clean', llmCall: stubLlm);
      expect(transitions, isEmpty);
    });

    test('fires on de-escalation with window', () async {
      final transitions = <(EscalationLevel, EscalationLevel)>[];
      final session = GuardSession(
        guard: AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 100,
          window: 2,
        ),
        onEscalation: (from, to) => transitions.add((from, to)),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(transitions, [(EscalationLevel.warn, EscalationLevel.block)]);
      await session.run(input: 'clean', llmCall: stubLlm);
      await session.run(input: 'clean', llmCall: stubLlm);
      expect(transitions.last, (EscalationLevel.block, EscalationLevel.warn));
    });
  });

  group('GuardSession.toJson / restore', () {
    test('round-trips session state', () async {
      final guard = AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]);
      final session = GuardSession(
        guard: guard,
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 10,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      await session.run(input: 'clean', llmCall: stubLlm);

      final json = session.toJson();
      final restored = GuardSession.restore(
        guard: guard,
        state: json,
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 10,
        ),
      );

      expect(restored.turnCount, session.turnCount);
      expect(restored.findingCounts, session.findingCounts);
      expect(restored.scannerCounts, session.scannerCounts);
      expect(restored.escalationLevel, session.escalationLevel);
    });

    test('restored session continues accumulating', () async {
      final guard = AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]);
      final session = GuardSession(
        guard: guard,
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 3,
          terminateThreshold: 100,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      final json = session.toJson();

      final restored = GuardSession.restore(
        guard: guard,
        state: json,
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 3,
          terminateThreshold: 100,
        ),
      );
      await restored.run(input: secret, llmCall: stubLlm);
      expect(restored.turnCount, 2);
      final totalFindings =
          restored.findingCounts.values.fold<int>(0, (a, b) => a + b);
      expect(totalFindings, greaterThan(1));
    });

    test('restored session preserves escalation level', () async {
      final guard = AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]);
      final session = GuardSession(
        guard: guard,
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 100,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);
      expect(session.escalationLevel, EscalationLevel.block);

      final restored = GuardSession.restore(
        guard: guard,
        state: session.toJson(),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 1,
          terminateThreshold: 100,
        ),
      );
      expect(restored.escalationLevel, EscalationLevel.block);
    });

    test('turnHistory is empty after restore', () async {
      final guard = AiGuard(inputScanners: [SecretScanner()]);
      final session = GuardSession(guard: guard);
      await session.run(input: 'clean', llmCall: stubLlm);

      final restored = GuardSession.restore(
        guard: guard,
        state: session.toJson(),
      );
      expect(restored.turnHistory, isEmpty);
      expect(restored.lastOutcome, isNull);
    });

    test('windowed escalation works after restore', () async {
      final guard = AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]);
      final session = GuardSession(
        guard: guard,
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 2,
          terminateThreshold: 100,
          window: 3,
        ),
      );
      await session.run(input: secret, llmCall: stubLlm);

      final restored = GuardSession.restore(
        guard: guard,
        state: session.toJson(),
        escalationPolicy: const EscalationPolicy(
          blockThreshold: 2,
          terminateThreshold: 100,
          window: 3,
        ),
      );
      // One finding in restored snapshots + one new = 2 >= blockThreshold
      await restored.run(input: secret, llmCall: stubLlm);
      expect(restored.escalationLevel, EscalationLevel.block);
    });

    test('toJson excludes text content', () async {
      final guard = AiGuard(inputScanners: [SecretScanner(action: GuardAction.warn)]);
      final session = GuardSession(guard: guard);
      await session.run(input: secret, llmCall: stubLlm);

      final json = session.toJson();
      final jsonStr = json.toString();
      expect(jsonStr, isNot(contains('AKIAIOSFODNN7EXAMPLE')));
    });
  });

  group('EscalationRule serialization', () {
    test('toJson / fromJson round-trips', () {
      const rule = EscalationRule(blockThreshold: 3, terminateThreshold: 7);
      final json = rule.toJson();
      final restored = EscalationRule.fromJson(json);
      expect(restored.blockThreshold, 3);
      expect(restored.terminateThreshold, 7);
    });
  });
}
