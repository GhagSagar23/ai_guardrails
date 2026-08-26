import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  final guard = AiGuard(
    inputScanners: [SecretScanner()],
  );

  Future<String> stubLlm(String input) async => 'ok: $input';

  group('GuardSession', () {
    test('delegates to AiGuard.run and returns outcome', () async {
      final session = GuardSession(guard: guard);
      final outcome = await session.run(input: 'hello', llmCall: stubLlm);
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'ok: hello');
    });

    test('turnCount starts at 0', () {
      final session = GuardSession(guard: guard);
      expect(session.turnCount, 0);
    });

    test('turnCount increments after each run', () async {
      final session = GuardSession(guard: guard);
      await session.run(input: 'a', llmCall: stubLlm);
      expect(session.turnCount, 1);
      await session.run(input: 'b', llmCall: stubLlm);
      expect(session.turnCount, 2);
    });

    test('turnCount increments even on blocked input', () async {
      final session = GuardSession(guard: guard);
      final outcome = await session.run(
        input: 'key AKIAIOSFODNN7EXAMPLE',
        llmCall: stubLlm,
      );
      expect(outcome.blocked, isTrue);
      expect(session.turnCount, 1);
    });

    test('reset clears turnCount', () async {
      final session = GuardSession(guard: guard);
      await session.run(input: 'a', llmCall: stubLlm);
      await session.run(input: 'b', llmCall: stubLlm);
      expect(session.turnCount, 2);
      session.reset();
      expect(session.turnCount, 0);
    });

    test('guard getter exposes wrapped AiGuard', () {
      final session = GuardSession(guard: guard);
      expect(session.guard, same(guard));
    });

    test('works with empty scanner lists', () async {
      final session = GuardSession(guard: AiGuard());
      final outcome = await session.run(input: 'anything', llmCall: stubLlm);
      expect(outcome.blocked, isFalse);
      expect(session.turnCount, 1);
    });

    test('multiple runs accumulate turns independently', () async {
      final s1 = GuardSession(guard: guard);
      final s2 = GuardSession(guard: guard);
      await s1.run(input: 'a', llmCall: stubLlm);
      await s1.run(input: 'b', llmCall: stubLlm);
      await s2.run(input: 'c', llmCall: stubLlm);
      expect(s1.turnCount, 2);
      expect(s2.turnCount, 1);
    });
  });
}
