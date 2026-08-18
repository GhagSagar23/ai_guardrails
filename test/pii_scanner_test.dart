import 'package:ai_guardrails/src/data/pii_patterns.dart';
import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/pii_scanner.dart';
import 'package:test/test.dart';

Set<String> _types(ScanResult r) => r.findings.map((f) => f.type).toSet();

void main() {
  group('detection across locales', () {
    test('US types: email, phone, ssn, ip', () {
      final r = PiiScanner(action: GuardAction.warn).scan(
        'Reach alice@example.com or 555-123-4567, SSN 123-45-6789, IP 192.168.1.1',
      );
      final t = _types(r);
      expect(t,
          containsAll(<String>['pii.email', 'pii.phone', 'pii.ssn', 'pii.ip']));
    });

    test('EU types: iban and eu phone', () {
      final r = PiiScanner(action: GuardAction.warn, locales: {PiiLocale.eu})
          .scan('IBAN DE89370400440532013000 call +44 20 7946 0958');
      final t = _types(r);
      expect(t, containsAll(<String>['pii.iban', 'pii.phone']));
    });

    test('India types: aadhaar, pan, mobile, passport', () {
      final r = PiiScanner(action: GuardAction.warn, locales: {
        PiiLocale.india
      }).scan(
          'Aadhaar 1234 5678 9012 PAN ABCDE1234F mob 9876543210 pp A1234567');
      final t = _types(r);
      expect(
          t,
          containsAll(
              <String>['pii.aadhaar', 'pii.pan', 'pii.phone', 'pii.passport']));
    });

    test('clean text passes with no findings', () {
      final r = PiiScanner().scan('nothing sensitive here, just plain words');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
      expect(r.score, 0.0);
      expect(r.text, 'nothing sensitive here, just plain words');
    });

    test('finding offsets index into the original text', () {
      const text = 'mail: bob@work.io done';
      final r = PiiScanner(action: GuardAction.warn).scan(text);
      final f = r.findings.single;
      expect(text.substring(f.start, f.end), f.match);
      expect(f.match, 'bob@work.io');
    });
  });

  group('Luhn handling for credit_card', () {
    final cc = PiiScanner(action: GuardAction.warn, types: {'credit_card'});

    test('valid Luhn number is detected', () {
      final r = cc.scan('card 4111 1111 1111 1111 end');
      expect(_types(r), {'pii.credit_card'});
    });

    test('invalid Luhn number is dropped', () {
      final r = cc.scan('card 4111 1111 1111 1112 end');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });
  });

  group('GuardAction paths', () {
    const emailText = 'email alice@example.com now';

    test('block: passed=false, non-zero score, text unchanged', () {
      final r = PiiScanner(action: GuardAction.block).scan(emailText);
      expect(r.passed, isFalse);
      expect(r.score, greaterThan(0.0));
      expect(r.text, emailText);
      expect(r.reason, contains('pii.email'));
    });

    test('redact: default placeholder, passed=true, modest score', () {
      final r = PiiScanner(action: GuardAction.redact).scan(emailText);
      expect(r.passed, isTrue);
      expect(r.text, 'email [EMAIL_1] now');
      expect(r.score, 0.5);
    });

    test('redact: custom placeholder callback wins', () {
      final r = PiiScanner(
        action: GuardAction.redact,
        placeholder: (f) => '***',
      ).scan(emailText);
      expect(r.text, 'email *** now');
    });

    test('hash: stable short token replaces the match', () {
      final scanner = PiiScanner(action: GuardAction.hash);
      final a = scanner.scan(emailText);
      final b = scanner.scan(emailText);
      expect(a.passed, isTrue);
      expect(a.text, matches(RegExp(r'email \[EMAIL:[0-9a-f]{6}\] now')));
      expect(a.text, b.text); // stable
    });

    test('warn: text unchanged, findings kept, score 0.5', () {
      final r = PiiScanner(action: GuardAction.warn).scan(emailText);
      expect(r.passed, isTrue);
      expect(r.text, emailText);
      expect(r.hasFindings, isTrue);
      expect(r.score, 0.5);
    });

    test('credit_card redacts with [CREDIT_CARD] and skips Luhn failures', () {
      final r = PiiScanner(action: GuardAction.redact, types: {'credit_card'})
          .scan('ok 4111 1111 1111 1111 bad 4111 1111 1111 1112');
      expect(r.text, 'ok [CREDIT_CARD_1] bad 4111 1111 1111 1112');
    });
  });

  group('overlap resolution', () {
    test('a credit card is not also reported as aadhaar', () {
      final r =
          PiiScanner(action: GuardAction.warn).scan('num 4111 1111 1111 1111');
      expect(_types(r), {'pii.credit_card'});
    });

    test('numeric-local email is not also reported as phone', () {
      final r =
          PiiScanner(action: GuardAction.warn).scan('4155550132@gmail.com');
      expect(_types(r), {'pii.email'});
      expect(r.findings.single.match, '4155550132@gmail.com');
    });

    test('non-overlapping PII of different types all survive', () {
      final r = PiiScanner(action: GuardAction.warn)
          .scan('4111111111111111 and 192.168.0.1');
      expect(_types(r), {'pii.credit_card', 'pii.ip'});
    });

    test('redacted text contains exactly one placeholder per finding', () {
      final r = PiiScanner().scan('num 4111 1111 1111 1111');
      expect(r.text, 'num [CREDIT_CARD_1]');
      expect('[CREDIT_CARD_1]'.allMatches(r.text).length, r.findings.length);
      expect(r.text.contains('[AADHAAR'), isFalse);
    });
  });

  group('redactionMap', () {
    test('redact populates map with numbered placeholders', () {
      final r = PiiScanner(action: GuardAction.redact, types: {'email'})
          .scan('a@b.com and c@d.com');
      expect(r.redactionMap, {
        '[EMAIL_1]': 'a@b.com',
        '[EMAIL_2]': 'c@d.com',
      });
      expect(r.text, '[EMAIL_1] and [EMAIL_2]');
    });

    test('hash populates map with hash tokens', () {
      final r = PiiScanner(action: GuardAction.hash, types: {'email'})
          .scan('a@b.com');
      expect(r.redactionMap.length, 1);
      final key = r.redactionMap.keys.single;
      expect(key, matches(RegExp(r'\[EMAIL:[0-9a-f]{6}\]')));
      expect(r.redactionMap[key], 'a@b.com');
    });

    test('block and warn produce empty map', () {
      for (final action in [GuardAction.block, GuardAction.warn]) {
        final r = PiiScanner(action: action, types: {'email'})
            .scan('a@b.com');
        expect(r.redactionMap, isEmpty);
      }
    });

    test('different PII types get independent counters', () {
      final r = PiiScanner(action: GuardAction.redact).scan(
        'a@b.com 123-45-6789 c@d.com',
      );
      expect(r.redactionMap.containsKey('[EMAIL_1]'), isTrue);
      expect(r.redactionMap.containsKey('[EMAIL_2]'), isTrue);
      expect(r.redactionMap.containsKey('[SSN_1]'), isTrue);
    });
  });

  group('filters', () {
    test('types filter keeps only requested pattern types', () {
      final r = PiiScanner(action: GuardAction.warn, types: {'email'})
          .scan('alice@example.com SSN 123-45-6789');
      expect(_types(r), {'pii.email'});
    });

    test('locales filter drops US-only patterns', () {
      final r = PiiScanner(action: GuardAction.warn, locales: {PiiLocale.india})
          .scan('SSN 123-45-6789');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('scanner metadata matches the frozen contract', () {
      final s = PiiScanner();
      expect(s.name, 'pii');
      expect(s.stages, {ScanStage.input, ScanStage.output});
    });
  });
}
