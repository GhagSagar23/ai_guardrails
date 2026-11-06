import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_scanners_example/ai_guardrails_scanners_example.dart';
import 'package:test/test.dart';

void main() {
  group('ExamplePlugin', () {
    late ScannerRegistry registry;
    late ScannerHub hub;

    setUp(() {
      registry = ScannerRegistry();
      hub = ScannerHub(registry: registry);
    });

    test('installs and registers both scanners', () {
      hub.install(ExamplePlugin());
      expect(registry.has('profanity'), true);
      expect(registry.has('word_count'), true);
    });

    test('metadata is correct', () {
      final plugin = ExamplePlugin();
      expect(plugin.name, 'example');
      expect(plugin.version, '0.1.0');
      expect(plugin.scannerNames, ['profanity', 'word_count']);
      expect(plugin.description, isNotEmpty);
    });

    test('const instance works', () {
      hub.install(examplePlugin);
      expect(hub.has('example'), true);
    });

    test('describe reports plugin info', () {
      hub.install(ExamplePlugin());
      final info = hub.describe();
      expect(info, hasLength(1));
      expect(info.first.name, 'example');
      expect(info.first.scannerNames, ['profanity', 'word_count']);
    });

    test('scanners build with config', () {
      hub.install(ExamplePlugin());
      final profanity = registry.build('profanity', {
        'words': ['test']
      });
      expect(profanity, isA<ProfanityScanner>());
      final wordCount = registry.build('word_count', {'maxWords': 10});
      expect(wordCount, isA<WordCountScanner>());
    });
  });

  group('ProfanityScanner', () {
    test('detects profanity', () {
      final scanner = ProfanityScanner();
      final result = scanner.scan('What the hell is this');
      expect(result.passed, false);
      expect(result.findings, isNotEmpty);
      expect(result.findings.first.type, 'profanity.hell');
    });

    test('passes clean text', () {
      final scanner = ProfanityScanner();
      final result = scanner.scan('Good morning');
      expect(result.passed, true);
    });

    test('custom word list', () {
      final scanner = ProfanityScanner(words: {'badword'});
      expect(scanner.scan('this is badword').passed, false);
      expect(scanner.scan('this is fine').passed, true);
    });

    test('warn action does not block', () {
      final scanner = ProfanityScanner(action: GuardAction.warn);
      final result = scanner.scan('What the hell');
      expect(result.passed, true);
      expect(result.findings, isNotEmpty);
    });

    test('finds multiple occurrences', () {
      final scanner = ProfanityScanner();
      final result = scanner.scan('damn it, damn again');
      expect(result.findings.length, 2);
    });

    test('case insensitive', () {
      final scanner = ProfanityScanner();
      final result = scanner.scan('DAMN');
      expect(result.passed, false);
    });

    test('runs on both stages', () {
      final scanner = ProfanityScanner();
      expect(scanner.stages, contains(ScanStage.input));
      expect(scanner.stages, contains(ScanStage.output));
    });
  });

  group('WordCountScanner', () {
    test('passes under limit', () {
      final scanner = WordCountScanner(maxWords: 5);
      final result = scanner.scan('one two three');
      expect(result.passed, true);
    });

    test('blocks over limit', () {
      final scanner = WordCountScanner(maxWords: 3);
      final result = scanner.scan('one two three four five');
      expect(result.passed, false);
      expect(result.reason, contains('5'));
      expect(result.reason, contains('3'));
    });

    test('exact limit passes', () {
      final scanner = WordCountScanner(maxWords: 3);
      final result = scanner.scan('one two three');
      expect(result.passed, true);
    });

    test('warn action does not block', () {
      final scanner = WordCountScanner(maxWords: 2, action: GuardAction.warn);
      final result = scanner.scan('one two three');
      expect(result.passed, true);
      expect(result.findings, isNotEmpty);
    });

    test('empty text passes', () {
      final scanner = WordCountScanner(maxWords: 1);
      final result = scanner.scan('');
      expect(result.passed, true);
    });
  });
}
