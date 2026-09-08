import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('CompetitorMentionScanner', () {
    test('blocks competitor mention', () {
      final s = CompetitorMentionScanner(['Acme', 'Globex']);
      final result = s.scan('You should try Acme instead');
      expect(result.passed, isFalse);
      expect(result.findings.first.type, 'competitor.Acme');
    });

    test('passes clean text', () {
      final s = CompetitorMentionScanner(['Acme']);
      final result = s.scan('Our product is the best');
      expect(result.passed, isTrue);
    });

    test('case insensitive by default', () {
      final s = CompetitorMentionScanner(['Acme']);
      final result = s.scan('Try acme today');
      expect(result.passed, isFalse);
    });

    test('case sensitive mode', () {
      final s = CompetitorMentionScanner(['Acme'], caseSensitive: true);
      expect(s.scan('Try Acme').passed, isFalse);
      expect(s.scan('Try acme').passed, isTrue);
    });

    test('multiple competitors', () {
      final s = CompetitorMentionScanner(['Acme', 'Globex']);
      final result = s.scan('Both Acme and Globex are options');
      expect(result.passed, isFalse);
      expect(result.findings.length, greaterThanOrEqualTo(2));
    });

    test('word boundary matching', () {
      final s = CompetitorMentionScanner(['Ace']);
      expect(s.scan('Ace is a competitor').passed, isFalse);
      expect(s.scan('Surface is nice').passed, isTrue);
    });

    test('redact mode', () {
      final s = CompetitorMentionScanner(['Acme'], action: GuardAction.redact);
      final result = s.scan('Try Acme today');
      expect(result.text, contains('[COMPETITOR]'));
      expect(result.text, isNot(contains('Acme')));
    });

    test('hash mode', () {
      final s = CompetitorMentionScanner(['Acme'], action: GuardAction.hash);
      final result = s.scan('Try Acme today');
      expect(result.text, contains('[COMPETITOR:'));
    });

    test('warn mode', () {
      final s = CompetitorMentionScanner(['Acme'], action: GuardAction.warn);
      final result = s.scan('Try Acme today');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('competitor_mention', {
        'competitors': ['Acme', 'Globex'],
      });
      expect(s, isA<CompetitorMentionScanner>());
    });
  });
}
