import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/schema_validator.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaValidator', () {
    test('valid object passes', () {
      final v = SchemaValidator({
        'type': 'object',
        'required': ['name'],
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'number'},
        },
      });
      final r = v.scan('{"name": "Ada", "age": 36}', stage: ScanStage.output);
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('invalid JSON blocks with a parse violation', () {
      final v = SchemaValidator({'type': 'object'});
      final r = v.scan('{not json', stage: ScanStage.output);
      expect(r.passed, isFalse);
      expect(r.score, 1.0);
      expect(r.findings.single.type, 'schema.parse');
      expect(r.reason, contains('invalid JSON'));
    });

    test('top-level type mismatch blocks', () {
      final v = SchemaValidator({'type': 'object'});
      final r = v.scan('[1, 2, 3]', stage: ScanStage.output);
      expect(r.passed, isFalse);
      expect(r.findings.single.type, 'schema.type');
    });

    test('missing required key blocks', () {
      final v = SchemaValidator({
        'type': 'object',
        'required': ['id', 'name'],
      });
      final r = v.scan('{"id": 1}', stage: ScanStage.output);
      expect(r.passed, isFalse);
      final f = r.findings.single;
      expect(f.type, 'schema.required');
      expect(f.match, 'name');
    });

    test('property type mismatch blocks', () {
      final v = SchemaValidator({
        'type': 'object',
        'properties': {
          'age': {'type': 'number'},
        },
      });
      final r = v.scan('{"age": "old"}', stage: ScanStage.output);
      expect(r.passed, isFalse);
      final f = r.findings.single;
      expect(f.type, 'schema.property');
      expect(f.match, 'age');
    });

    test('warn action reports without blocking', () {
      final v = SchemaValidator(
        {
          'type': 'object',
          'required': ['x']
        },
        action: GuardAction.warn,
      );
      final r = v.scan('{}', stage: ScanStage.output);
      expect(r.passed, isTrue);
      expect(r.score, 0.5);
      expect(r.findings.single.type, 'schema.required');
    });

    test('array top-level type validates', () {
      final v = SchemaValidator({'type': 'array'});
      expect(v.scan('[1,2]', stage: ScanStage.output).passed, isTrue);
      expect(v.scan('{}', stage: ScanStage.output).passed, isFalse);
    });

    test('scalar top-level types validate', () {
      expect(
          SchemaValidator({'type': 'string'})
              .scan('"hi"', stage: ScanStage.output)
              .passed,
          isTrue);
      expect(
          SchemaValidator({'type': 'number'})
              .scan('42', stage: ScanStage.output)
              .passed,
          isTrue);
      expect(
          SchemaValidator({'type': 'boolean'})
              .scan('true', stage: ScanStage.output)
              .passed,
          isTrue);
      expect(
          SchemaValidator({'type': 'boolean'})
              .scan('"true"', stage: ScanStage.output)
              .passed,
          isFalse);
    });

    test('multiple violations are all listed', () {
      final v = SchemaValidator({
        'type': 'object',
        'required': ['a', 'b'],
        'properties': {
          'c': {'type': 'number'},
        },
      });
      final r = v.scan('{"c": "nope"}', stage: ScanStage.output);
      expect(r.passed, isFalse);
      // 2 missing required + 1 bad property
      expect(r.findings, hasLength(3));
      expect(r.reason, contains('a'));
      expect(r.reason, contains('b'));
      expect(r.reason, contains('c'));
    });

    test('only runs on the output stage', () {
      final v = SchemaValidator({'type': 'object'});
      expect(v.stages, {ScanStage.output});
    });
  });
}
