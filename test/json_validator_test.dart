import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('JsonValidator', () {
    test('passes valid JSON', () {
      final v = JsonValidator();
      final result = v.scan('{"key": "value"}');
      expect(result.passed, isTrue);
    });

    test('blocks invalid JSON syntax', () {
      final v = JsonValidator();
      final result = v.scan('{not json}');
      expect(result.passed, isFalse);
      expect(result.findings.first.type, 'json_validator.parse');
    });

    test('blocks excessive nesting depth', () {
      final v = JsonValidator(maxDepth: 3);
      final nested = '${List.generate(5, (_) => '{"a":').join()}'
          '"x"'
          '${List.generate(5, (_) => '}').join()}';
      final result = v.scan(nested);
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'json_validator.depth'), isTrue);
    });

    test('blocks excessive array length', () {
      final v = JsonValidator(maxArrayLength: 3);
      final arr = jsonEncode(List.generate(5, (i) => i));
      final result = v.scan(arr);
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'json_validator.array_length'),
          isTrue);
    });

    test('blocks excessive key count', () {
      final v = JsonValidator(maxKeyCount: 2);
      final obj = jsonEncode({'a': 1, 'b': 2, 'c': 3});
      final result = v.scan(obj);
      expect(result.passed, isFalse);
      expect(result.findings.any((f) => f.type == 'json_validator.key_count'),
          isTrue);
    });

    test('passes within limits', () {
      final v =
          JsonValidator(maxDepth: 10, maxArrayLength: 100, maxKeyCount: 50);
      final result = v.scan('{"a": [1, 2, 3], "b": {"c": true}}');
      expect(result.passed, isTrue);
    });

    test('warn mode passes with findings', () {
      final v = JsonValidator(action: GuardAction.warn);
      final result = v.scan('{bad');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('output stage only', () {
      final v = JsonValidator();
      expect(v.stages, {ScanStage.output});
    });

    test('registry builds with defaults', () {
      final s = ScannerRegistry.instance.build('json_validator');
      expect(s, isA<JsonValidator>());
    });

    test('registry builds with config', () {
      final s = ScannerRegistry.instance.build('json_validator', {
        'maxDepth': 5,
        'maxArrayLength': 100,
        'action': 'warn',
      });
      expect(s, isA<JsonValidator>());
    });
  });
}
