import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('FactCheckScanner', () {
    test('passes when LLM says SUPPORTED', () async {
      final scanner =
          FactCheckScanner(context: 'The Eiffel Tower is in Paris.');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'SUPPORTED\nThe claim matches the context.',
      );

      final results =
          await guard.scanOutput('The Eiffel Tower is located in Paris.');
      expect(results.single.passed, isTrue);
      expect(results.single.findings, isEmpty);
    });

    test('flags contradiction', () async {
      final scanner =
          FactCheckScanner(context: 'The Eiffel Tower is in Paris.');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async =>
            'CONTRADICTED\nThe text says London, but context says Paris.',
      );

      final results = await guard.scanOutput('The Eiffel Tower is in London.');
      expect(results.single.passed, isTrue); // warn action
      expect(results.single.findings, hasLength(1));
      expect(results.single.findings.first.type, 'factcheck.contradiction');
      expect(results.single.score, 1.0);
      expect(results.single.findings.first.match, contains('London'));
    });

    test('flags unsupported claims', () async {
      final scanner =
          FactCheckScanner(context: 'The Eiffel Tower is in Paris.');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async =>
            'UNSUPPORTED\nThe height claim is not in the context.',
      );

      final results =
          await guard.scanOutput('The Eiffel Tower is 324 meters tall.');
      expect(results.single.passed, isTrue); // warn action
      expect(results.single.findings.first.type, 'factcheck.unsupported');
      expect(results.single.score, 0.7);
    });

    test('blocks with action block', () async {
      final scanner = FactCheckScanner(
        context: 'X is true.',
        action: GuardAction.block,
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'CONTRADICTED\nWrong.',
      );

      final results = await guard.scanOutput('X is false.');
      expect(results.single.passed, isFalse);
    });

    test('passes empty text', () async {
      final scanner = FactCheckScanner(context: 'some context');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => fail('should not be called'),
      );

      final results = await guard.scanOutput('');
      expect(results.single.passed, isTrue);
    });

    test('is output-stage only', () {
      final scanner = FactCheckScanner(context: 'ctx');
      expect(scanner.stages, {ScanStage.output});
    });

    test('handles verdict with no explanation', () async {
      final scanner = FactCheckScanner(context: 'ctx');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'CONTRADICTED',
      );

      final results = await guard.scanOutput('something');
      expect(results.single.findings.first.type, 'factcheck.contradiction');
      expect(results.single.findings.first.match, isNull);
    });
  });
}
