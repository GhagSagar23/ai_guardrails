import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('HallucinationScanner', () {
    test('passes when LLM judges consistent', () async {
      var callCount = 0;
      final scanner = HallucinationScanner(prompt: 'What is 2+2?');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async {
          callCount++;
          if (callCount <= 3) return 'The answer is 4.';
          return 'CONSISTENT';
        },
      );

      final results = await guard.scanOutput('The answer is 4.');
      expect(results.single.passed, isTrue);
      expect(callCount, 4); // 3 samples + 1 judgment
    });

    test('flags inconsistent claims', () async {
      var callCount = 0;
      final scanner = HallucinationScanner(prompt: 'What is 2+2?');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async {
          callCount++;
          if (callCount <= 3) return 'The answer is 4.';
          return 'INCONSISTENT\n- The capital claim is fabricated';
        },
      );

      final results = await guard.scanOutput('The answer is 4 and Paris.');
      expect(results.single.passed, isTrue); // warn action passes
      expect(results.single.findings, hasLength(1));
      expect(results.single.findings.first.type,
          'hallucination.inconsistent_claim');
      expect(results.single.findings.first.match,
          'The capital claim is fabricated');
    });

    test('blocks with action block', () async {
      var callCount = 0;
      final scanner = HallucinationScanner(
        prompt: 'Q?',
        action: GuardAction.block,
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async {
          callCount++;
          if (callCount <= 3) return 'answer';
          return 'INCONSISTENT\n- bad claim';
        },
      );

      final results = await guard.scanOutput('some output');
      expect(results.single.passed, isFalse);
    });

    test('respects custom sampleCount', () async {
      var callCount = 0;
      final scanner = HallucinationScanner(prompt: 'Q?', sampleCount: 5);
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async {
          callCount++;
          if (callCount <= 5) return 'sample';
          return 'CONSISTENT';
        },
      );

      await guard.scanOutput('output');
      expect(callCount, 6); // 5 samples + 1 judgment
    });

    test('passes empty text', () async {
      final scanner = HallucinationScanner(prompt: 'Q?');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => fail('should not be called'),
      );

      final results = await guard.scanOutput('');
      expect(results.single.passed, isTrue);
    });

    test('handles INCONSISTENT with no listed claims', () async {
      var callCount = 0;
      final scanner = HallucinationScanner(prompt: 'Q?');
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async {
          callCount++;
          if (callCount <= 3) return 'sample';
          return 'INCONSISTENT';
        },
      );

      final results = await guard.scanOutput('some text');
      expect(results.single.findings, hasLength(1));
      expect(results.single.findings.first.match, isNull);
    });

    test('is output-stage only', () {
      final scanner = HallucinationScanner(prompt: 'Q?');
      expect(scanner.stages, {ScanStage.output});
    });
  });
}
