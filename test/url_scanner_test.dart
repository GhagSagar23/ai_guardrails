import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/url_scanner.dart';
import 'package:test/test.dart';

Set<String> _types(ScanResult r) => r.findings.map((f) => f.type).toSet();

void main() {
  group('UrlScanner', () {
    final scanner = UrlScanner();

    test('clean URL passes', () {
      final r = scanner.scan('Visit https://example.com for more info');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('IP-literal URL is flagged', () {
      final r = scanner.scan('Go to http://192.168.1.1/admin');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.ip_literal'));
    });

    test('data: URI is flagged', () {
      final r = scanner.scan('src="data:text/html,<script>alert(1)</script>"');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.data_uri'));
    });

    test('javascript: URI is flagged', () {
      final r = scanner.scan('href="javascript:alert(1)"');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.javascript_uri'));
    });

    test('suspicious TLD is flagged', () {
      final r = scanner.scan('Check https://login-secure.tk/account');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.suspicious_tld'));
    });

    test('URL shortener is flagged', () {
      final r = scanner.scan('Click https://bit.ly/abc123');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.shortener'));
    });

    test('punycode domain is flagged', () {
      final r = scanner.scan('Visit https://xn--pple-43d.com/login');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.punycode'));
    });

    test('credentials in URL are flagged', () {
      final r = scanner.scan('Use http://admin:pass123@internal.corp/api');
      expect(r.passed, isFalse);
      expect(_types(r), contains('url.credentials'));
    });

    test('warn action passes with findings', () {
      final s = UrlScanner(action: GuardAction.warn);
      final r = s.scan('Go to http://192.168.1.1/admin');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
    });

    test('category filter limits checks', () {
      final s =
          UrlScanner(categories: const {UrlCategory.dataUri});
      final r = s.scan('Go to http://192.168.1.1/admin');
      expect(r.passed, isTrue);
    });

    test('text without URLs passes', () {
      final r = scanner.scan('Just some plain text, no links here.');
      expect(r.passed, isTrue);
    });

    test('multiple findings in one text', () {
      final r = scanner.scan(
        'Visit http://192.168.1.1 and https://evil.tk/phish',
      );
      expect(r.passed, isFalse);
      expect(r.findings.length, greaterThanOrEqualTo(2));
    });

    test('scanner metadata', () {
      expect(scanner.name, 'url');
      expect(scanner.stages, {ScanStage.input, ScanStage.output});
    });
  });
}
