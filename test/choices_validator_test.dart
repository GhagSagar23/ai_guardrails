import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('ChoicesValidator', () {
    test('passes matching choice', () {
      final v = ChoicesValidator(['yes', 'no', 'maybe']);
      expect(v.scan('yes').passed, isTrue);
    });

    test('blocks non-matching', () {
      final v = ChoicesValidator(['yes', 'no']);
      final result = v.scan('perhaps');
      expect(result.passed, isFalse);
      expect(result.findings.first.type, 'choices_validator.invalid');
    });

    test('case insensitive by default', () {
      final v = ChoicesValidator(['Yes', 'No']);
      expect(v.scan('YES').passed, isTrue);
      expect(v.scan('yes').passed, isTrue);
    });

    test('case sensitive mode', () {
      final v = ChoicesValidator(['Yes', 'No'], caseSensitive: true);
      expect(v.scan('Yes').passed, isTrue);
      expect(v.scan('yes').passed, isFalse);
    });

    test('trims whitespace by default', () {
      final v = ChoicesValidator(['yes', 'no']);
      expect(v.scan('  yes  ').passed, isTrue);
    });

    test('trim disabled', () {
      final v = ChoicesValidator(['yes'], trim: false);
      expect(v.scan('  yes  ').passed, isFalse);
    });

    test('truncates long match in finding', () {
      final v = ChoicesValidator(['a']);
      final result = v.scan('x' * 100);
      expect(result.findings.first.match!.length, lessThan(60));
    });

    test('warn mode', () {
      final v = ChoicesValidator(['a'], action: GuardAction.warn);
      final result = v.scan('b');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('choices_validator', {
        'choices': ['red', 'green', 'blue'],
      });
      expect(s, isA<ChoicesValidator>());
    });
  });
}
