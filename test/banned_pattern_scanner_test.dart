import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/banned_pattern_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('BannedPatternScanner detection', () {
    test('literal string pattern matches with offsets and match text', () {
      final r = BannedPatternScanner(
        ['forbidden'],
        action: GuardAction.warn,
      ).scan('this is forbidden text');
      expect(r.hasFindings, isTrue);
      final f = r.findings.single;
      expect(f.type, 'banned_pattern.match');
      expect(f.match, 'forbidden');
      expect('this is forbidden text'.substring(f.start, f.end), 'forbidden');
    });

    test('RegExp pattern matches', () {
      final r = BannedPatternScanner(
        [RegExp(r'\bdrugs?\b', caseSensitive: false)],
        action: GuardAction.warn,
      ).scan('no Drug here');
      expect(r.hasFindings, isTrue);
      expect(r.findings.single.match, 'Drug');
    });

    test('every pattern is matched, findings accumulate', () {
      final r = BannedPatternScanner(
        ['foo', RegExp(r'ba[rz]')],
        action: GuardAction.warn,
      ).scan('foo bar baz foo');
      // two 'foo' + 'bar' + 'baz'
      expect(r.findings.length, 4);
    });

    test('clean text passes with no findings', () {
      final r = BannedPatternScanner(['nope']).scan('nothing to see here');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
      expect(r.score, 0.0);
      expect(r.text, 'nothing to see here');
    });
  });

  group('BannedPatternScanner configurable name', () {
    test('name getter and ScanResult.scanner use the configured name', () {
      final scanner = BannedPatternScanner(['x'],
          name: 'profanity', action: GuardAction.warn);
      expect(scanner.name, 'profanity');
      final r = scanner.scan('x marks it');
      expect(r.scanner, 'profanity');
    });

    test('defaults to "banned_pattern"', () {
      expect(BannedPatternScanner(const []).name, 'banned_pattern');
    });
  });

  group('BannedPatternScanner actions', () {
    test('block: passed=false, reason set, non-zero score', () {
      final r = BannedPatternScanner(['bad']).scan('a bad thing');
      expect(r.passed, isFalse);
      expect(r.reason, isNotNull);
      expect(r.score, greaterThan(0.0));
      expect(r.text, 'a bad thing');
    });

    test('redact: replaces every match with [BANNED]', () {
      final r = BannedPatternScanner(
        ['foo'],
        action: GuardAction.redact,
      ).scan('foo bar foo');
      expect(r.passed, isTrue);
      expect(r.text, '[BANNED] bar [BANNED]');
      expect(r.score, 0.5);
    });

    test('hash: replaces with a stable [BANNED:token]', () {
      final a = BannedPatternScanner(
        ['secret'],
        action: GuardAction.hash,
      ).scan('a secret value');
      final b = BannedPatternScanner(
        ['secret'],
        action: GuardAction.hash,
      ).scan('a secret value');
      expect(a.text, contains('[BANNED:'));
      expect(a.text, isNot(contains('secret')));
      expect(a.text, b.text);
      expect(a.passed, isTrue);
    });

    test('warn: keeps findings, text unchanged, passes', () {
      final r = BannedPatternScanner(
        ['warnme'],
        action: GuardAction.warn,
      ).scan('please warnme now');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
      expect(r.text, 'please warnme now');
      expect(r.score, 0.5);
    });
  });
}
