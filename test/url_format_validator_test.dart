import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('UrlFormatValidator', () {
    test('passes http/https URLs by default', () {
      final v = UrlFormatValidator();
      final result = v.scan('Visit https://example.com for details');
      expect(result.passed, isTrue);
    });

    test('blocks disallowed protocols', () {
      final v = UrlFormatValidator();
      final result = v.scan('Download from ftp://files.example.com/data');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'url_format_validator.protocol'),
          isTrue);
    });

    test('blocks URLs with credentials', () {
      final v = UrlFormatValidator();
      final result = v.scan('http://admin:password@example.com');
      expect(result.passed, isFalse);
      expect(
          result.findings
              .any((f) => f.type == 'url_format_validator.credentials'),
          isTrue);
    });

    test('domain allowlist blocks non-matching', () {
      final v = UrlFormatValidator(allowedDomains: {'example.com'});
      final result = v.scan('See https://evil.com/page');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'url_format_validator.domain'),
          isTrue);
    });

    test('domain allowlist passes matching', () {
      final v = UrlFormatValidator(allowedDomains: {'example.com'});
      final result = v.scan('See https://example.com/page');
      expect(result.passed, isTrue);
    });

    test('no URLs in text passes', () {
      final v = UrlFormatValidator();
      final result = v.scan('No URLs here');
      expect(result.passed, isTrue);
    });

    test('credentials check can be disabled', () {
      final v = UrlFormatValidator(blockCredentials: false);
      final result = v.scan('http://user:pass@example.com');
      expect(result.passed, isTrue);
    });

    test('custom protocols', () {
      final v = UrlFormatValidator(allowedProtocols: {'https'});
      expect(v.scan('https://ok.com').passed, isTrue);
      expect(v.scan('http://not-ok.com').passed, isFalse);
    });

    test('warn mode', () {
      final v = UrlFormatValidator(action: GuardAction.warn);
      final result = v.scan('ftp://bad.com');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('url_format_validator');
      expect(s, isA<UrlFormatValidator>());
    });
  });
}
