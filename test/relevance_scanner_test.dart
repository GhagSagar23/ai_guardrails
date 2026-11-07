import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails/src/data/stop_words.dart';
import 'package:test/test.dart';

const _q = 'What is the weather forecast in London tomorrow?';
const _good =
    'The weather forecast for London tomorrow is rainy with mild temperatures.';
const _bad = 'Preheat the oven and simmer the tomato sauce with fresh basil '
    'before baking the pizza dough.';

ScanResult _out(RelevanceScanner s, String text) =>
    s.scan(text, stage: ScanStage.output);

void main() {
  group('RelevanceScanner', () {
    test('relevant answer passes', () {
      final r = _out(RelevanceScanner(referenceText: _q), _good);
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('irrelevant answer is flagged with relevance.low_score', () {
      final r = _out(RelevanceScanner(referenceText: _q), _bad);
      expect(r.hasFindings, isTrue);
      expect(r.findings.single.type, 'relevance.low_score');
      expect(r.findings.single.match, isNotNull);
    });

    test('refusal detected', () {
      final s = RelevanceScanner(referenceText: _q);
      final r = _out(s, 'I cannot help with that weather forecast request.');
      expect(r.hasFindings, isTrue);
      expect(s.relevanceScore('I cannot help with that', _q), 0.0);
    });

    test('multiple refusal patterns detected', () {
      final s = RelevanceScanner(referenceText: _q);
      for (final t in [
        "I'm sorry, I can't tell you the London weather forecast tomorrow.",
        'As an AI, I do not know the weather forecast in London tomorrow.',
        'I am unable to give the weather forecast in London tomorrow.',
        'I’m sorry but the weather forecast in London tomorrow is hidden.',
      ]) {
        expect(s.relevanceScore(t, _q), 0.0, reason: t);
        expect(_out(s, t).hasFindings, isTrue, reason: t);
      }
    });

    test('threshold configuration works', () {
      final partial = 'London will be cold.';
      final lenient = RelevanceScanner(referenceText: _q, minRelevance: 0.01);
      final strict = RelevanceScanner(referenceText: _q, minRelevance: 0.99);
      expect(_out(lenient, partial).hasFindings, isFalse);
      expect(_out(strict, partial).hasFindings, isTrue);
    });

    test('very short output penalized', () {
      final s = RelevanceScanner(referenceText: _q);
      expect(s.relevanceScore('London', _q),
          lessThan(s.relevanceScore(_good, _q)));
      expect(_out(s, 'London').hasFindings, isTrue);
    });

    test('action warn passes with findings by default', () {
      final r = _out(RelevanceScanner(referenceText: _q), _bad);
      expect(r.passed, isTrue);
    });

    test('action block fails', () {
      final r = _out(
        RelevanceScanner(referenceText: _q, action: GuardAction.block),
        _bad,
      );
      expect(r.passed, isFalse);
      expect(r.hasFindings, isTrue);
    });

    test('output stage only', () {
      final s = RelevanceScanner(referenceText: _q);
      expect(s.stages, {ScanStage.output});
      expect(s.scan(_bad, stage: ScanStage.input).hasFindings, isFalse);
    });

    test('null or blank reference passes', () {
      expect(_out(RelevanceScanner(), _bad).hasFindings, isFalse);
      expect(_out(RelevanceScanner(referenceText: '   '), _bad).hasFindings,
          isFalse);
    });

    test('referenceText can be set after construction', () {
      final s = RelevanceScanner();
      expect(_out(s, _bad).hasFindings, isFalse);
      s.referenceText = _q;
      expect(_out(s, _bad).hasFindings, isTrue);
    });

    test('empty output gets zero-ish score and finding', () {
      final s = RelevanceScanner(referenceText: _q);
      expect(s.relevanceScore('', _q), 0.0);
      expect(_out(s, '').hasFindings, isTrue);
    });

    test('score is within 0.0..1.0', () {
      final s = RelevanceScanner(referenceText: _q);
      for (final t in ['', _good, _bad, _q, _q * 5, 'x', 'I cannot']) {
        final v = s.relevanceScore(t, _q);
        expect(v, inInclusiveRange(0.0, 1.0), reason: t);
      }
    });

    test('stop words are filtered', () {
      final s = RelevanceScanner();
      // Only stop words shared -> no content overlap -> low score.
      expect(s.relevanceScore('the is of and to in a', 'what is the of to in'),
          1.0); // reference has no content words -> nothing to compare
      expect(
        s.relevanceScore(
            'the and of is to in cooking pasta', 'the and of is to in weather'),
        lessThan(0.5),
      );
      expect(relevanceStopWords, containsAll(['the', 'and', 'is']));
    });

    test('case insensitive', () {
      final s = RelevanceScanner();
      expect(s.relevanceScore(_good.toUpperCase(), _q),
          s.relevanceScore(_good.toLowerCase(), _q));
    });

    test('partial keyword overlap gives partial score', () {
      final s = RelevanceScanner();
      final full = s.relevanceScore(_good, _q);
      final part = s.relevanceScore(
          'The forecast says London is lovely and nice today friend.', _q);
      expect(part, greaterThan(0.0));
      expect(part, lessThan(full));
    });

    test('perfect echo scores high', () {
      expect(RelevanceScanner().relevanceScore(_q, _q), closeTo(1.0, 1e-9));
    });

    test('registry builds scanner from config', () {
      final s = ScannerRegistry.instance.build('relevance', {
        'minRelevance': 0.9,
        'action': 'block',
        'referenceText': _q,
      }) as RelevanceScanner;
      expect(s.minRelevance, 0.9);
      expect(s.action, GuardAction.block);
      expect(s.referenceText, _q);
    });
  });
}
