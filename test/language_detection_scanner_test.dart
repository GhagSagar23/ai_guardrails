import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('LanguageDetectionScanner', () {
    test('English passes when en allowed', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('The quick brown fox jumps over the lazy dog');
      expect(r.passed, true);
    });

    test('Spanish blocked when only en allowed', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan(
          'Todos los seres humanos nacen libres e iguales en dignidad y derechos');
      expect(r.passed, false);
      expect(r.findings.first.type, 'language_detection.detected');
      expect(r.findings.first.match, 'es');
    });

    test('French detected', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan(
          'Tous les êtres humains naissent libres et égaux en dignité et en droits');
      expect(r.passed, false);
      expect(r.findings.first.match, 'fr');
    });

    test('German detected', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan(
          'Alle Menschen sind frei und gleich an Würde und Rechten geboren');
      expect(r.passed, false);
      expect(r.findings.first.match, 'de');
    });

    test('Italian detected', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan(
          'Tutti gli esseri umani nascono liberi e uguali in dignità e diritti');
      expect(r.passed, false);
      expect(r.findings.first.match, 'it');
    });

    test('Portuguese detected', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan(
          'Todos os seres humanos nascem livres e iguais em dignidade e em direitos');
      expect(r.passed, false);
      expect(r.findings.first.match, 'pt');
    });

    test('Japanese detected via script', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('すべての人間は、生まれながらにして自由であり');
      expect(r.passed, false);
      expect(r.findings.first.match, 'ja');
    });

    test('Chinese detected via script', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('人人生而自由在尊严和权利上一律平等');
      expect(r.passed, false);
      expect(r.findings.first.match, 'zh');
    });

    test('Korean detected via script', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('모든 인간은 태어날 때부터 자유로우며');
      expect(r.passed, false);
      expect(r.findings.first.match, 'ko');
    });

    test('Hindi detected via script', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('सभी मनुष्यों को गौरव और अधिकारों के मामले में जन्मजात');
      expect(r.passed, false);
      expect(r.findings.first.match, 'hi');
    });

    test('Russian detected via script', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('Все люди рождаются свободными и равными');
      expect(r.passed, false);
      expect(r.findings.first.match, 'ru');
    });

    test('short text passes regardless', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('Hola');
      expect(r.passed, true);
    });

    test('empty text passes', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan('');
      expect(r.passed, true);
    });

    test('multiple allowed languages', () {
      final s = LanguageDetectionScanner(allow: {'en', 'es', 'fr'});
      final r = s.scan(
          'Todos los seres humanos nacen libres e iguales en dignidad y derechos');
      expect(r.passed, true);
    });

    test('action warn passes with findings', () {
      final s =
          LanguageDetectionScanner(allow: {'en'}, action: GuardAction.warn);
      final r = s.scan(
          'Todos los seres humanos nacen libres e iguales en dignidad y derechos');
      expect(r.passed, true);
      expect(r.findings, isNotEmpty);
    });

    test('confidence score is between 0 and 1', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      final r = s.scan(
          'Todos los seres humanos nacen libres e iguales en dignidad y derechos');
      expect(r.findings.first.confidence, greaterThanOrEqualTo(0.0));
      expect(r.findings.first.confidence, lessThanOrEqualTo(1.0));
    });

    test('input stage only', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      expect(s.stages, {ScanStage.input});
    });

    test('name is language_detection', () {
      final s = LanguageDetectionScanner(allow: {'en'});
      expect(s.name, 'language_detection');
    });

    test('script language passes when in allow set', () {
      final s = LanguageDetectionScanner(allow: {'ja'});
      final r = s.scan('すべての人間は、生まれながらにして自由であり');
      expect(r.passed, true);
    });

    test('registry builds from config', () {
      final scanner = ScannerRegistry.instance.build('language_detection', {
        'allow': ['en', 'fr'],
        'minConfidence': 0.5,
        'action': 'warn',
      });
      expect(scanner, isA<LanguageDetectionScanner>());
    });

    test('assert fails with empty allow set', () {
      expect(
        () => LanguageDetectionScanner(allow: {}),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
