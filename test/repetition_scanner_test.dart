import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/repetition_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('RepetitionScanner', () {
    final scanner = RepetitionScanner();

    test('clean text passes', () {
      final r = scanner.scan('The quick brown fox jumps over the lazy dog');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('highly repetitive text blocks', () {
      final r = scanner.scan(
        'buy now buy now buy now buy now buy now buy now',
      );
      expect(r.passed, isFalse);
      expect(r.score, greaterThan(0.3));
      expect(r.findings.first.type, 'repetition.ngram');
      expect(r.reason, contains('repetition'));
    });

    test('short text below ngram threshold passes', () {
      final r = scanner.scan('hello world');
      expect(r.passed, isTrue);
    });

    test('warn action passes with findings', () {
      final s = RepetitionScanner(action: GuardAction.warn);
      final r = s.scan('go go go go go go go go go go go go');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
    });

    test('custom threshold adjusts sensitivity', () {
      const text = 'a b c d e f a b c d e f a b c';
      final loose = RepetitionScanner(threshold: 0.8).scan(text);
      final tight = RepetitionScanner(threshold: 0.1).scan(text);
      expect(loose.passed, isTrue);
      expect(tight.passed, isFalse);
    });

    test('only runs on output stage', () {
      final s = RepetitionScanner();
      expect(s.stages, {ScanStage.output});
    });

    test('findings report most-repeated ngrams first', () {
      final r = scanner.scan(
        'x y z x y z x y z x y z a b c a b c',
      );
      if (r.hasFindings && r.findings.length >= 2) {
        expect(r.findings.first.confidence,
            greaterThanOrEqualTo(r.findings.last.confidence));
      }
    });
  });
}
