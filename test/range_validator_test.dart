import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('RangeValidator', () {
    test('passes value in numeric range', () {
      final v = RangeValidator(min: 0, max: 100);
      expect(v.scan('42').passed, isTrue);
    });

    test('blocks value below min', () {
      final v = RangeValidator(min: 10);
      final result = v.scan('5');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'range_validator.min'), isTrue);
    });

    test('blocks value above max', () {
      final v = RangeValidator(max: 100);
      final result = v.scan('200');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'range_validator.max'), isTrue);
    });

    test('blocks non-numeric when range set', () {
      final v = RangeValidator(min: 0);
      final result = v.scan('hello');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'range_validator.not_numeric'),
          isTrue);
    });

    test('string length min', () {
      final v = RangeValidator(minLength: 5);
      expect(v.scan('hi').passed, isFalse);
      expect(v.scan('hello world').passed, isTrue);
    });

    test('string length max', () {
      final v = RangeValidator(maxLength: 5);
      expect(v.scan('hi').passed, isTrue);
      expect(v.scan('hello world').passed, isFalse);
    });

    test('combined numeric and length', () {
      final v = RangeValidator(min: 0, max: 100, minLength: 1, maxLength: 3);
      expect(v.scan('42').passed, isTrue);
      expect(v.scan('1000').passed, isFalse);
    });

    test('no constraints passes everything', () {
      final v = RangeValidator();
      expect(v.scan('anything').passed, isTrue);
    });

    test('handles decimals', () {
      final v = RangeValidator(min: 0.5, max: 1.5);
      expect(v.scan('1.0').passed, isTrue);
      expect(v.scan('0.1').passed, isFalse);
    });

    test('trims whitespace for numeric parse', () {
      final v = RangeValidator(min: 0, max: 100);
      expect(v.scan('  50  ').passed, isTrue);
    });

    test('warn mode', () {
      final v = RangeValidator(min: 10, action: GuardAction.warn);
      final result = v.scan('5');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('range_validator', {
        'min': 0,
        'max': 100,
      });
      expect(s, isA<RangeValidator>());
    });
  });
}
