import 'package:ai_guardrails/src/data/pii_patterns.dart';
import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/pii_scanner.dart';
import 'package:test/test.dart';

Set<String> _types(ScanResult r) => r.findings.map((f) => f.type).toSet();

void main() {
  group('Brazil', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.brazil});

    test('CPF detected', () {
      final r = scanner.scan('CPF 123.456.789-09');
      expect(_types(r), contains('pii.cpf'));
    });

    test('CNPJ detected', () {
      final r = scanner.scan('CNPJ 12.345.678/0001-95');
      expect(_types(r), contains('pii.cnpj'));
    });

    test('Brazil phone detected', () {
      final r = scanner.scan('call +55 11 98765-4321');
      expect(_types(r), contains('pii.phone'));
    });
  });

  group('Mexico', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.mexico});

    test('CURP detected', () {
      final r = scanner.scan('CURP GARC850101HDFRRL09');
      expect(_types(r), contains('pii.curp'));
    });

    test('RFC detected', () {
      final r = scanner.scan('RFC GARC850101AB3');
      expect(_types(r), contains('pii.rfc'));
    });
  });

  group('Japan', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.japan});

    test('My Number detected', () {
      final r = scanner.scan('My Number 1234 5678 9012');
      expect(_types(r), contains('pii.my_number'));
    });

    test('Japan phone detected', () {
      final r = scanner.scan('call +813-1234-5678');
      expect(_types(r), contains('pii.phone'));
    });
  });

  group('South Korea', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.southKorea});

    test('RRN detected', () {
      final r = scanner.scan('RRN 850101-1234567');
      expect(_types(r), contains('pii.rrn'));
    });

    test('Korea phone detected', () {
      final r = scanner.scan('call +8210-1234-5678');
      expect(_types(r), contains('pii.phone'));
    });
  });

  group('Canada', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.canada});

    test('SIN detected (Luhn-valid)', () {
      // 046-454-286 is Luhn-valid
      final r = scanner.scan('SIN 046-454-286');
      expect(_types(r), contains('pii.sin'));
    });

    test('SIN with invalid Luhn is dropped', () {
      final r = scanner.scan('SIN 123-456-780');
      expect(r.findings.where((f) => f.type == 'pii.sin'), isEmpty);
    });
  });

  group('Australia', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.australia});

    test('TFN detected', () {
      final r = scanner.scan('TFN 123 456 789');
      expect(_types(r), contains('pii.tfn'));
    });

    test('Medicare detected', () {
      final r = scanner.scan('Medicare 2123 45670 1');
      expect(_types(r), contains('pii.medicare'));
    });

    test('Australia phone detected', () {
      final r = scanner.scan('call +61 4 1234 5678');
      expect(_types(r), contains('pii.phone'));
    });
  });

  group('EU country-specific phones', () {
    final scanner =
        PiiScanner(action: GuardAction.warn, locales: {PiiLocale.eu});

    test('UK phone', () {
      final r = scanner.scan('call +44 20 7946 0958');
      expect(_types(r), contains('pii.phone'));
    });

    test('German phone', () {
      final r = scanner.scan('call +49 30 12345678');
      expect(_types(r), contains('pii.phone'));
    });

    test('French phone', () {
      final r = scanner.scan('call +33 1 23 45 67 89');
      expect(_types(r), contains('pii.phone'));
    });

    test('Italian phone', () {
      final r = scanner.scan('call +39 06 12345678');
      expect(_types(r), contains('pii.phone'));
    });

    test('Spanish phone', () {
      final r = scanner.scan('call +34 912 345 678');
      expect(_types(r), contains('pii.phone'));
    });
  });

  group('RTL text with PII', () {
    test('email in Arabic text detected with correct offsets', () {
      const text = 'البريد الإلكتروني هو user@example.com للتواصل';
      final r = PiiScanner(action: GuardAction.warn).scan(text);
      expect(_types(r), contains('pii.email'));
      final f = r.findings.firstWhere((f) => f.type == 'pii.email');
      expect(text.substring(f.start, f.end), 'user@example.com');
    });

    test('email in Hebrew text detected', () {
      const text = 'שלח דואר אל test@domain.org בבקשה';
      final r = PiiScanner(action: GuardAction.warn).scan(text);
      expect(_types(r), contains('pii.email'));
    });

    test('credit card in mixed bidi text detected', () {
      const text = 'رقم البطاقة 4111 1111 1111 1111 شكرا';
      final r = PiiScanner(action: GuardAction.warn).scan(text);
      expect(_types(r), contains('pii.credit_card'));
    });

    test('PII redaction in RTL text preserves structure', () {
      const text = 'البريد user@example.com ثم رقم 123-45-6789 هنا';
      final r = PiiScanner(action: GuardAction.redact).scan(text);
      expect(r.text, contains('[EMAIL_1]'));
      expect(r.text, contains('[SSN_1]'));
      expect(r.text, contains('البريد'));
      expect(r.text, contains('هنا'));
    });
  });

  group('locale filtering', () {
    test('brazil locale excludes US SSN', () {
      final r = PiiScanner(
        action: GuardAction.warn,
        locales: {PiiLocale.brazil},
      ).scan('SSN 123-45-6789');
      expect(r.findings.where((f) => f.type == 'pii.ssn'), isEmpty);
    });

    test('multiple new locales work together', () {
      final r = PiiScanner(
        action: GuardAction.warn,
        locales: {PiiLocale.brazil, PiiLocale.japan},
      ).scan('CPF 123.456.789-09 and My Number 1234 5678 9012');
      expect(_types(r), containsAll(['pii.cpf', 'pii.my_number']));
    });
  });
}
