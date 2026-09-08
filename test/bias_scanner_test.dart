import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('BiasScanner', () {
    test('passes neutral text', () async {
      final s = BiasScanner();
      final result = await s.scanAsync('The weather is nice today.');
      expect(result.passed, isTrue);
    });

    test('detects gender generalisation', () async {
      final s = BiasScanner();
      final result = await s.scanAsync('All women are bad at math.');
      expect(result.passed, isTrue); // default action is warn
      expect(result.hasFindings, isTrue);
      expect(result.findings.any((f) => f.type == 'bias.gender_generalisation'),
          isTrue);
    });

    test('detects age stereotype', () async {
      final s = BiasScanner();
      final result =
          await s.scanAsync('Old people are always confused by technology.');
      expect(result.hasFindings, isTrue);
      expect(
          result.findings.any((f) => f.type == 'bias.age_stereotype'), isTrue);
    });

    test('detects racial generalisation', () async {
      final s = BiasScanner();
      final result = await s.scanAsync('All black people are good at sports.');
      expect(result.hasFindings, isTrue);
      expect(result.findings.any((f) => f.type == 'bias.racial_generalisation'),
          isTrue);
    });

    test('detects gender role bias', () async {
      final s = BiasScanner();
      final result = await s.scanAsync('Women belong in the kitchen.');
      expect(result.hasFindings, isTrue);
      expect(result.findings.any((f) => f.type == 'bias.gender_role'), isTrue);
    });

    test('block mode', () async {
      final s = BiasScanner(action: GuardAction.block);
      final result = await s.scanAsync('All men are always aggressive.');
      expect(result.passed, isFalse);
    });

    test('LLM mode calls callback when heuristic clean', () async {
      final s = BiasScanner(useLlm: true);
      var called = false;
      s.llmCallback = (prompt) async {
        called = true;
        return 'NONE';
      };
      await s.scanAsync('The weather is nice.');
      expect(called, isTrue);
    });

    test('LLM mode returns findings', () async {
      final s = BiasScanner(useLlm: true);
      s.llmCallback = (prompt) async => 'BIAS: Subtle age assumption';
      final result = await s.scanAsync('Millennials are lazy.');
      expect(result.hasFindings, isTrue);
      expect(result.findings.any((f) => f.type == 'bias.llm'), isTrue);
    });

    test('output stage only', () {
      final s = BiasScanner();
      expect(s.stages, {ScanStage.output});
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('bias');
      expect(s, isA<BiasScanner>());
    });
  });
}
