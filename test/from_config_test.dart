import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('AiGuard.fromConfig', () {
    test('builds guard from JSON config with multiple scanners', () async {
      final guard = AiGuard.fromConfig({
        'failClosed': true,
        'inputScanners': [
          {
            'type': 'pii',
            'action': 'redact',
            'locales': ['us']
          },
          {'type': 'secret'},
          {'type': 'prompt_injection', 'threshold': 0.5},
        ],
        'outputScanners': [
          {'type': 'repetition', 'threshold': 0.3},
        ],
      });

      final outcome = await guard.run(
        input: 'email a@b.com is fine',
        llmCall: (s) async => 'normal response',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.input, contains('[EMAIL_1]'));
    });

    test('config with schema validator works', () async {
      final guard = AiGuard.fromConfig({
        'outputScanners': [
          {
            'type': 'schema',
            'schema': {
              'type': 'object',
              'required': ['name'],
              'properties': {
                'name': {'type': 'string'}
              },
            },
          },
        ],
      });
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async => '{"name": "Ada"}',
      );
      expect(outcome.blocked, isFalse);
    });

    test('config with banned topics', () async {
      final guard = AiGuard.fromConfig({
        'inputScanners': [
          {
            'type': 'banned_topic',
            'topics': ['medical advice'],
          },
        ],
      });
      final outcome = await guard.run(
        input: 'give me medical advice',
        llmCall: (s) async => 'ok',
      );
      expect(outcome.blocked, isTrue);
    });

    test('config with banned patterns', () async {
      final guard = AiGuard.fromConfig({
        'inputScanners': [
          {
            'type': 'banned_pattern',
            'patterns': [r'INTERNAL-\d{6}'],
            'name': 'leak_guard',
          },
        ],
      });
      final outcome = await guard.run(
        input: 'see INTERNAL-004821',
        llmCall: (s) async => 'ok',
      );
      expect(outcome.blocked, isTrue);
    });

    test('all scanner types are recognized', () {
      final scannerTypes = [
        'pii',
        'secret',
        'prompt_injection',
        'invisible_text',
        'token_limit',
        'repetition',
        'url',
        'language',
        'code_exec',
        'grounding',
        'schema',
      ];
      for (final type in scannerTypes) {
        final config = <String, dynamic>{'type': type};
        if (type == 'banned_topic') config['topics'] = ['x'];
        if (type == 'banned_pattern') config['patterns'] = ['x'];
        if (type == 'schema') {
          config['schema'] = {'type': 'object'};
        }
        // Should not throw
        AiGuard.fromConfig({
          'inputScanners': [config],
        });
      }
    });

    test('unknown scanner type throws', () {
      expect(
        () => AiGuard.fromConfig({
          'inputScanners': [
            {'type': 'nonexistent'}
          ],
        }),
        throwsArgumentError,
      );
    });

    test('unknown action throws', () {
      expect(
        () => AiGuard.fromConfig({
          'inputScanners': [
            {'type': 'pii', 'action': 'explode'}
          ],
        }),
        throwsArgumentError,
      );
    });

    test('failClosed defaults to true', () async {
      final guard = AiGuard.fromConfig({});
      expect(guard.failClosed, isTrue);
    });

    test('onScan and onMetrics wire through fromConfig', () async {
      var scanFired = false;
      var metricsFired = false;
      final guard = AiGuard.fromConfig(
        {},
        onScan: (_) => scanFired = true,
        onMetrics: (_) => metricsFired = true,
      );
      await guard.run(input: 'hi', llmCall: (s) async => 'ok');
      expect(scanFired, isTrue);
      expect(metricsFired, isTrue);
    });
  });
}
