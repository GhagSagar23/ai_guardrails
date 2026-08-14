import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/token_limit_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('TokenLimitScanner', () {
    test('under limit passes clean', () {
      final s = TokenLimitScanner(maxTokens: 10);
      final r = s.scan('just a few words here');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
      expect(r.score, 0.0);
    });

    test('empty string passes', () {
      final s = TokenLimitScanner(maxTokens: 1);
      final r = s.scan('');
      expect(r.passed, isTrue);
      expect(s.estimateTokens(''), 0);
    });

    test('over limit blocks with count in reason', () {
      final s = TokenLimitScanner(maxTokens: 3);
      final r = s.scan('one two three four five');
      expect(r.passed, isFalse);
      expect(r.score, 1.0);
      expect(r.findings.single.type, 'token_limit.exceeded');
      expect(r.reason, contains('5'));
      expect(r.reason, contains('> 3'));
    });

    test('exactly at limit passes (not strictly greater)', () {
      final s = TokenLimitScanner(maxTokens: 3);
      final r = s.scan('one two three');
      expect(r.passed, isTrue);
    });

    test('warn action over limit does not block', () {
      final s = TokenLimitScanner(maxTokens: 2, action: GuardAction.warn);
      final r = s.scan('one two three');
      expect(r.passed, isTrue);
      expect(r.score, 0.5);
      expect(r.findings.single.type, 'token_limit.exceeded');
      expect(r.reason, contains('3'));
    });

    test('redact action is treated as warn (no block)', () {
      final s = TokenLimitScanner(maxTokens: 2, action: GuardAction.redact);
      final r = s.scan('one two three');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
    });

    test('hash action is treated as warn (no block)', () {
      final s = TokenLimitScanner(maxTokens: 2, action: GuardAction.hash);
      final r = s.scan('one two three');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
    });

    test('estimateTokens counts word and punctuation runs', () {
      final s = TokenLimitScanner();
      // "hello" "," "world" "!!" => 4 tokens
      expect(s.estimateTokens('hello, world!!'), 4);
      // punctuation run counts once: "a" "..." "b" => 3
      expect(s.estimateTokens('a...b'), 3);
    });

    test('only runs on the input stage', () {
      final s = TokenLimitScanner();
      expect(s.stages, {ScanStage.input});
    });
  });
}
