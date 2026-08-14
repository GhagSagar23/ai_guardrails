import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/secret_scanner.dart';
import 'package:test/test.dart';

/// Convenience: the set of `secret.<kind>` suffixes in a result.
Set<String> _kinds(ScanResult r) =>
    {for (final f in r.findings) f.type.split('.').last};

void main() {
  group('SecretScanner detection', () {
    test('detects an AWS access key and offsets point at it', () {
      const key = 'AKIAIOSFODNN7EXAMPLE';
      final r = SecretScanner(action: GuardAction.warn).scan('creds: $key');
      expect(_kinds(r), contains('aws_access_key'));
      final f = r.findings.firstWhere((f) => f.type == 'secret.aws_access_key');
      expect('creds: $key'.substring(f.start, f.end), key);
    });

    test('detects a contextual AWS secret access key', () {
      const secret = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
      final text = 'aws_secret_access_key = $secret';
      final r = SecretScanner(action: GuardAction.warn).scan(text);
      expect(_kinds(r), contains('aws_secret'));
      final f = r.findings.firstWhere((f) => f.type == 'secret.aws_secret');
      // Only the 40-char token, not the surrounding context, is spanned.
      expect(text.substring(f.start, f.end), secret);
    });

    test('detects a GCP API key', () {
      const key = 'AIza' 'SyD-abc123_DEF456ghiJKL789mnoPQRstu';
      final r = SecretScanner(action: GuardAction.warn).scan('key=$key');
      expect(_kinds(r), contains('gcp_api_key'));
    });

    test('detects a GitHub token', () {
      const key = 'ghp_0123456789abcdefghij0123456789abcdef';
      final r = SecretScanner(action: GuardAction.warn).scan('token $key');
      expect(_kinds(r), contains('github_token'));
    });

    test('detects an OpenAI key', () {
      const key = 'sk-abcdefghij0123456789ABCD';
      final r = SecretScanner(action: GuardAction.warn).scan('OPENAI=$key');
      expect(_kinds(r), contains('openai_key'));
    });

    test('detects a Slack token', () {
      const key = 'xoxb-' '1234567890-abcdefGHIJ';
      final r = SecretScanner(action: GuardAction.warn).scan('slack: $key');
      expect(_kinds(r), contains('slack_token'));
    });

    test('detects a JWT', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      final r = SecretScanner(action: GuardAction.warn).scan('auth $jwt');
      expect(_kinds(r), contains('jwt'));
    });

    test('detects a PEM private key block', () {
      const pem =
          '-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKj34\n-----END RSA PRIVATE KEY-----';
      final r = SecretScanner(action: GuardAction.warn).scan(pem);
      expect(_kinds(r), contains('private_key_block'));
    });

    test('reports several secrets in one string', () {
      const text =
          'a AKIAIOSFODNN7EXAMPLE and sk-abcdefghij0123456789ABCD together';
      final r = SecretScanner(action: GuardAction.warn).scan(text);
      expect(_kinds(r), containsAll(<String>{'aws_access_key', 'openai_key'}));
    });
  });

  group('SecretScanner clean pass', () {
    test('benign prose does not false-positive', () {
      const text =
          'Hello, my name is Sagar. I drew up the laws and released version 2.0.';
      final r = SecretScanner().scan(text);
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
      expect(r.score, 0.0);
      expect(r.text, text);
    });
  });

  group('SecretScanner actions', () {
    const key = 'sk-abcdefghij0123456789ABCD';
    final text = 'my key is $key ok';

    test('block: passed=false, reason set, non-zero score', () {
      final r = SecretScanner().scan(text); // default action is block
      expect(r.passed, isFalse);
      expect(r.reason, isNotNull);
      expect(r.score, greaterThan(0.0));
      expect(r.text, text); // block leaves text unchanged
    });

    test('redact: replaces the secret, passes through', () {
      final r = SecretScanner(action: GuardAction.redact).scan(text);
      expect(r.passed, isTrue);
      expect(r.text, contains('[OPENAI_KEY]'));
      expect(r.text, isNot(contains(key)));
      expect(r.score, 0.5);
    });

    test('hash: replaces with a stable short token', () {
      final a = SecretScanner(action: GuardAction.hash).scan(text);
      final b = SecretScanner(action: GuardAction.hash).scan(text);
      expect(a.text, contains('[OPENAI_KEY:'));
      expect(a.text, isNot(contains(key)));
      expect(a.text, b.text); // deterministic
      expect(a.passed, isTrue);
    });

    test('warn: keeps findings, text unchanged, passes', () {
      final r = SecretScanner(action: GuardAction.warn).scan(text);
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
      expect(r.text, text);
      expect(r.score, 0.5);
    });
  });
}
