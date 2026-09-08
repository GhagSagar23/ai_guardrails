import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('PolitenessScanner', () {
    test('passes neutral text for neutral target', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.neutral);
      final result = s.scan('The report shows a 10% increase in sales.');
      expect(result.passed, isTrue);
    });

    test('detects casual tone', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.formal);
      final result =
          s.scan("Yeah dude, gonna wanna check this out, it's pretty lit tbh");
      expect(result.hasFindings, isTrue);
      expect(result.findings.first.type, 'politeness.casual');
    });

    test('detects formal tone', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.casual);
      final result = s.scan(
          'Furthermore, notwithstanding the aforementioned circumstances, '
          'we must henceforth pursue this matter accordingly.');
      expect(result.hasFindings, isTrue);
      expect(result.findings.first.type, 'politeness.formal');
    });

    test('contractions signal casual', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.formal);
      final result =
          s.scan("It's clear that they're going to need help. We'd better "
              "start now. They'll agree it's the right approach.");
      expect(result.hasFindings, isTrue);
    });

    test('passes matching register', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.casual);
      final result = s.scan("Yeah gonna check this out, it's pretty cool lol");
      expect(result.passed, isTrue);
    });

    test('empty text passes', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.formal);
      final result = s.scan('');
      expect(result.passed, isTrue);
    });

    test('block mode', () {
      final s = PolitenessScanner(
        targetRegister: ToneRegister.formal,
        action: GuardAction.block,
      );
      final result = s.scan("lol yeah gonna do that bruh ngl it's wild");
      expect(result.passed, isFalse);
    });

    test('output stage only', () {
      final s = PolitenessScanner(targetRegister: ToneRegister.neutral);
      expect(s.stages, {ScanStage.output});
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('politeness', {
        'targetRegister': 'formal',
      });
      expect(s, isA<PolitenessScanner>());
    });

    test('registry defaults to neutral', () {
      final s = ScannerRegistry.instance.build('politeness');
      expect(s, isA<PolitenessScanner>());
    });
  });
}
