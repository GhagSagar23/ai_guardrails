import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/language_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('LanguageScanner', () {
    final scanner = LanguageScanner();

    test('English text passes with Latin expected', () {
      final r = scanner.scan('This is a perfectly normal English sentence.');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('Cyrillic-dominant text blocks when Latin expected', () {
      final r = scanner.scan('Привет мир, это тестовое сообщение для проверки');
      expect(r.passed, isFalse);
      expect(r.findings.first.match, 'cyrillic');
    });

    test('CJK text blocks when Latin expected', () {
      final r = scanner.scan('这是一个测试消息用来验证语言检测器的功能是否正常工作');
      expect(r.passed, isFalse);
      expect(r.findings.first.match, 'cjk');
    });

    test('Devanagari text blocks when Latin expected', () {
      final r =
          scanner.scan('यह एक परीक्षण संदेश है जो भाषा का पता लगाने के लिए है');
      expect(r.passed, isFalse);
      expect(r.findings.first.match, 'devanagari');
    });

    test('short text is ignored (below 10 classified chars)', () {
      final r = scanner.scan('Привет');
      expect(r.passed, isTrue);
    });

    test('expected Cyrillic passes Cyrillic text', () {
      final s = LanguageScanner(
        expectedScripts: const {UnicodeScript.cyrillic},
      );
      final r = s.scan('Привет мир, это тестовое сообщение для проверки');
      expect(r.passed, isTrue);
    });

    test('multiple expected scripts both pass', () {
      final s = LanguageScanner(
        expectedScripts: const {UnicodeScript.latin, UnicodeScript.cyrillic},
      );
      final r = s.scan('Hello Привет mixed text with both scripts together');
      expect(r.passed, isTrue);
    });

    test('warn action passes with findings', () {
      final s = LanguageScanner(action: GuardAction.warn);
      final r = s.scan('Привет мир, это тестовое сообщение для проверки');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
    });

    test('threshold adjusts sensitivity', () {
      const mixedText =
          'Hello world Привет мир mixed text here more English words';
      final loose = LanguageScanner(threshold: 0.3).scan(mixedText);
      final tight = LanguageScanner(threshold: 0.95).scan(mixedText);
      expect(loose.passed, isTrue);
      expect(tight.passed, isFalse);
    });

    test('Arabic script detected', () {
      final r =
          scanner.scan('مرحبا بالعالم هذه رسالة اختبار للتحقق من كشف اللغة');
      expect(r.passed, isFalse);
      expect(r.findings.first.match, 'arabic');
    });

    test('scanner metadata', () {
      expect(scanner.name, 'language');
      expect(scanner.stages, {ScanStage.input, ScanStage.output});
    });
  });
}
