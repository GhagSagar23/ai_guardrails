import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

class _StubScanner implements Scanner {
  @override
  String get name => 'stub';
  @override
  Set<ScanStage> get stages => const {ScanStage.input};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.pass(name, text);
}

void main() {
  group('ScannerRegistry', () {
    test('instance has all built-in scanners', () {
      final reg = ScannerRegistry.instance;
      const builtins = [
        'pii',
        'secret',
        'prompt_injection',
        'invisible_text',
        'banned_topic',
        'banned_pattern',
        'token_limit',
        'repetition',
        'url',
        'language',
        'code_exec',
        'grounding',
        'schema',
        'tool_call',
        'hallucination',
        'fact_check',
        'topic_safety',
      ];
      for (final name in builtins) {
        expect(reg.has(name), isTrue, reason: '$name not registered');
      }
    });

    test('build returns correct scanner type', () {
      final reg = ScannerRegistry.instance;
      expect(reg.build('pii'), isA<PiiScanner>());
      expect(reg.build('secret'), isA<SecretScanner>());
      expect(reg.build('prompt_injection'), isA<PromptInjectionScanner>());
    });

    test('build passes config to factory', () {
      final reg = ScannerRegistry.instance;
      final scanner =
          reg.build('repetition', {'threshold': 0.5, 'ngramSize': 4});
      expect(scanner, isA<RepetitionScanner>());
    });

    test('register custom scanner', () {
      final reg = ScannerRegistry();
      final stub = _StubScanner();
      reg.registerInstance('my_stub', stub);
      expect(reg.has('my_stub'), isTrue);
      expect(reg.build('my_stub'), same(stub));
    });

    test('register custom factory', () {
      final reg = ScannerRegistry();
      reg.register('custom', (cfg) {
        final threshold = (cfg['threshold'] as num?)?.toDouble() ?? 0.5;
        return PromptInjectionScanner(threshold: threshold);
      });
      final s = reg.build('custom', {'threshold': 0.8});
      expect(s, isA<PromptInjectionScanner>());
    });

    test('unregister removes scanner', () {
      final reg = ScannerRegistry();
      reg.registerInstance('temp', _StubScanner());
      expect(reg.has('temp'), isTrue);
      reg.unregister('temp');
      expect(reg.has('temp'), isFalse);
    });

    test('build throws for unknown scanner', () {
      final reg = ScannerRegistry();
      expect(() => reg.build('nonexistent'), throwsArgumentError);
    });

    test('tryBuild returns null for unknown scanner', () {
      final reg = ScannerRegistry();
      expect(reg.tryBuild('nonexistent'), isNull);
    });

    test('registered lists all names', () {
      final reg = ScannerRegistry();
      reg.registerInstance('a', _StubScanner());
      reg.registerInstance('b', _StubScanner());
      expect(reg.registered, containsAll(['a', 'b']));
    });

    test('fromConfig uses registry for scanner lookup', () {
      final reg = ScannerRegistry();
      reg.registerInstance('my_scanner', _StubScanner());
      final guard = AiGuard.fromConfig({
        'inputScanners': ['my_scanner'],
      }, registry: reg);
      expect(guard.inputScanners, hasLength(1));
      expect(guard.inputScanners.first, isA<_StubScanner>());
    });

    test('fromConfig supports mixed string and object scanners', () {
      final reg = ScannerRegistry();
      reg.registerBuiltins();
      final guard = AiGuard.fromConfig({
        'inputScanners': [
          'secret',
          {'type': 'pii', 'action': 'redact'},
        ],
      }, registry: reg);
      expect(guard.inputScanners, hasLength(2));
      expect(guard.inputScanners[0], isA<SecretScanner>());
      expect(guard.inputScanners[1], isA<PiiScanner>());
    });

    test('hallucination factory requires prompt', () {
      final reg = ScannerRegistry.instance;
      expect(() => reg.build('hallucination'), throwsArgumentError);
      expect(() => reg.build('hallucination', {'prompt': ''}),
          throwsArgumentError);
    });

    test('fact_check factory requires context', () {
      final reg = ScannerRegistry.instance;
      expect(() => reg.build('fact_check'), throwsArgumentError);
      expect(
          () => reg.build('fact_check', {'context': ''}), throwsArgumentError);
    });

    test('topic_safety factory with topics', () {
      final reg = ScannerRegistry.instance;
      final s = reg.build('topic_safety', {
        'allowedTopics': ['math'],
      });
      expect(s, isA<TopicSafetyScanner>());
    });
  });
}
