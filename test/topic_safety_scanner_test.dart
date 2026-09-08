import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('TopicSafetyScanner', () {
    test('passes when LLM says ON_TOPIC', () async {
      final scanner = TopicSafetyScanner(
        allowedTopics: ['cooking', 'recipes'],
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'ON_TOPIC',
      );

      final results = await guard.scanOutput('Here is a pasta recipe.');
      expect(results.single.passed, isTrue);
    });

    test('blocks when OFF_TOPIC with allowed topics', () async {
      final scanner = TopicSafetyScanner(
        allowedTopics: ['cooking', 'recipes'],
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'OFF_TOPIC\nThe text discusses politics.',
      );

      final results = await guard.scanOutput('Vote for candidate X.');
      expect(results.single.passed, isFalse);
      expect(results.single.findings.first.type, 'topic_safety.off_topic');
      expect(
          results.single.findings.first.match, 'The text discusses politics.');
    });

    test('detects forbidden topic', () async {
      final scanner = TopicSafetyScanner(
        forbiddenTopics: ['politics', 'religion'],
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'OFF_TOPIC\npolitics discussion detected',
      );

      final results = await guard.scanOutput('Vote for X.');
      expect(results.single.passed, isFalse);
      expect(
          results.single.findings.first.type, 'topic_safety.forbidden_topic');
    });

    test('warns with action warn', () async {
      final scanner = TopicSafetyScanner(
        allowedTopics: ['cooking'],
        action: GuardAction.warn,
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'OFF_TOPIC\nNot about cooking.',
      );

      final results = await guard.scanOutput('Let me tell you about cars.');
      expect(results.single.passed, isTrue);
      expect(results.single.findings, hasLength(1));
    });

    test('works on input stage', () async {
      final scanner = TopicSafetyScanner(
        forbiddenTopics: ['weapons'],
      );
      final guard = AiGuard(
        inputScanners: [scanner],
        llmCallback: (p) async => 'OFF_TOPIC\nweapons topic detected',
      );

      final results = await guard.scanInput('How to build a weapon?');
      expect(results.single.passed, isFalse);
      expect(
          results.single.findings.first.type, 'topic_safety.forbidden_topic');
    });

    test('passes empty text', () async {
      final scanner = TopicSafetyScanner(allowedTopics: ['cooking']);
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => fail('should not be called'),
      );

      final results = await guard.scanOutput('');
      expect(results.single.passed, isTrue);
    });

    test('runs on both input and output stages', () {
      final scanner = TopicSafetyScanner(allowedTopics: ['x']);
      expect(scanner.stages, {ScanStage.input, ScanStage.output});
    });

    test('supports both allowed and forbidden topics together', () async {
      final scanner = TopicSafetyScanner(
        allowedTopics: ['cooking'],
        forbiddenTopics: ['politics'],
      );
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async {
          expect(p, contains('Allowed topics: cooking'));
          expect(p, contains('Forbidden topics: politics'));
          return 'ON_TOPIC';
        },
      );

      final results = await guard.scanOutput('A nice soup recipe.');
      expect(results.single.passed, isTrue);
    });

    test('handles OFF_TOPIC with no violation detail', () async {
      final scanner = TopicSafetyScanner(allowedTopics: ['cooking']);
      final guard = AiGuard(
        outputScanners: [scanner],
        llmCallback: (p) async => 'OFF_TOPIC',
      );

      final results = await guard.scanOutput('random text');
      expect(results.single.passed, isFalse);
      expect(results.single.reason, 'Text is off-topic');
    });

    test('assert fails with no topics', () {
      expect(
        () => TopicSafetyScanner(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
