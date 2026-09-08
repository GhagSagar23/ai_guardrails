import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('SqlValidator', () {
    test('passes SELECT by default', () {
      final v = SqlValidator();
      final result = v.scan('SELECT * FROM users WHERE id = 1');
      expect(result.passed, isTrue);
    });

    test('blocks DROP', () {
      final v = SqlValidator();
      final result = v.scan('DROP TABLE users');
      expect(result.passed, isFalse);
      expect(result.findings.first.type, 'sql_validator.DROP');
    });

    test('blocks DELETE', () {
      final v = SqlValidator();
      final result = v.scan('DELETE FROM users WHERE id = 1');
      expect(result.passed, isFalse);
    });

    test('blocks ALTER', () {
      final v = SqlValidator();
      final result = v.scan('ALTER TABLE users ADD COLUMN name TEXT');
      expect(result.passed, isFalse);
    });

    test('blocks INSERT', () {
      final v = SqlValidator();
      final result = v.scan("INSERT INTO users VALUES (1, 'test')");
      expect(result.passed, isFalse);
    });

    test('blocks TRUNCATE', () {
      final v = SqlValidator();
      final result = v.scan('TRUNCATE TABLE users');
      expect(result.passed, isFalse);
    });

    test('case insensitive', () {
      final v = SqlValidator();
      final result = v.scan('drop table users');
      expect(result.passed, isFalse);
    });

    test('ignores statements in comments', () {
      final v = SqlValidator();
      final result = v.scan('SELECT 1 -- DROP TABLE users');
      expect(result.passed, isTrue);
    });

    test('ignores block comments', () {
      final v = SqlValidator();
      final result = v.scan('SELECT 1 /* DROP TABLE users */');
      expect(result.passed, isTrue);
    });

    test('custom allowed statements', () {
      final v = SqlValidator(allowedStatements: {'SELECT', 'INSERT'});
      expect(v.scan('INSERT INTO t VALUES (1)').passed, isTrue);
      expect(v.scan('SELECT 1').passed, isTrue);
      expect(v.scan('DELETE FROM t').passed, isFalse);
    });

    test('multi-statement detection', () {
      final v = SqlValidator();
      final result = v.scan('SELECT 1; DROP TABLE users;');
      expect(result.passed, isFalse);
    });

    test('warn mode', () {
      final v = SqlValidator(action: GuardAction.warn);
      final result = v.scan('DROP TABLE users');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('passes plain text without SQL', () {
      final v = SqlValidator();
      final result = v.scan('Just a regular sentence about databases.');
      expect(result.passed, isTrue);
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('sql_validator');
      expect(s, isA<SqlValidator>());
    });
  });
}
