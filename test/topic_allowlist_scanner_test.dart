import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('TopicAllowlistScanner', () {
    test('passes text matching allowed topic', () async {
      final s = TopicAllowlistScanner(allowedTopics: ['cooking', 'recipes']);
      final result = await s.scanAsync('Here is a great cooking tip');
      expect(result.passed, isTrue);
    });

    test('blocks text not matching any topic', () async {
      final s = TopicAllowlistScanner(allowedTopics: ['cooking', 'recipes']);
      final result = await s.scanAsync('The stock market crashed today');
      expect(result.passed, isFalse);
      expect(result.findings.first.type, 'topic_allowlist.off_topic');
    });

    test('case insensitive matching', () async {
      final s = TopicAllowlistScanner(allowedTopics: ['Science']);
      final result = await s.scanAsync('New science discovery announced');
      expect(result.passed, isTrue);
    });

    test('empty topics passes everything', () async {
      final s = TopicAllowlistScanner(allowedTopics: []);
      final result = await s.scanAsync('anything goes');
      expect(result.passed, isTrue);
    });

    test('word boundary matching', () async {
      final s = TopicAllowlistScanner(allowedTopics: ['art']);
      expect((await s.scanAsync('Modern art exhibition')).passed, isTrue);
      expect((await s.scanAsync('The party was great')).passed, isFalse);
    });

    test('warn mode', () async {
      final s = TopicAllowlistScanner(
        allowedTopics: ['cooking'],
        action: GuardAction.warn,
      );
      final result = await s.scanAsync('Stock market news');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('LLM mode calls callback', () async {
      final s = TopicAllowlistScanner(
        allowedTopics: ['cooking'],
        useLlm: true,
      );
      s.llmCallback = (prompt) async => 'yes';
      final result = await s.scanAsync('Something about food');
      expect(result.passed, isTrue);
    });

    test('LLM mode blocks on no', () async {
      final s = TopicAllowlistScanner(
        allowedTopics: ['cooking'],
        useLlm: true,
      );
      s.llmCallback = (prompt) async => 'no';
      final result = await s.scanAsync('Stock market crash');
      expect(result.passed, isFalse);
    });

    test('output stage only', () {
      final s = TopicAllowlistScanner(allowedTopics: ['test']);
      expect(s.stages, {ScanStage.output});
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('topic_allowlist', {
        'allowedTopics': ['cooking', 'baking'],
      });
      expect(s, isA<TopicAllowlistScanner>());
    });
  });
}
