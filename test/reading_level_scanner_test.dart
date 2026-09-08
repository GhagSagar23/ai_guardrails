import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('ReadingLevelScanner', () {
    final simpleText = 'The cat sat on the mat. The dog ran fast. '
        'It was a fun day. We had a good time.';
    final complexText =
        'Notwithstanding the aforementioned epistemological considerations, '
        'the phenomenological implications of quantum entanglement necessitate '
        'a comprehensive reevaluation of contemporary metaphysical paradigms '
        'and their concomitant methodological frameworks.';

    test('passes text within grade range', () {
      final s = ReadingLevelScanner(minGrade: 0, maxGrade: 20);
      expect(s.scan(simpleText).passed, isTrue);
    });

    test('detects too-simple text', () {
      final s = ReadingLevelScanner(minGrade: 10);
      final result = s.scan(simpleText);
      expect(result.hasFindings, isTrue);
      expect(result.findings.any((f) => f.type == 'reading_level.too_simple'),
          isTrue);
    });

    test('detects too-complex text', () {
      final s = ReadingLevelScanner(maxGrade: 5);
      final result = s.scan(complexText);
      expect(result.hasFindings, isTrue);
      expect(result.findings.any((f) => f.type == 'reading_level.too_complex'),
          isTrue);
    });

    test('short text passes (under 3 words)', () {
      final s = ReadingLevelScanner(minGrade: 10);
      expect(s.scan('Hi there').passed, isTrue);
    });

    test('no constraints passes everything', () {
      final s = ReadingLevelScanner();
      expect(s.scan(complexText).passed, isTrue);
      expect(s.scan(simpleText).passed, isTrue);
    });

    test('block mode', () {
      final s = ReadingLevelScanner(maxGrade: 3, action: GuardAction.block);
      final result = s.scan(complexText);
      expect(result.passed, isFalse);
    });

    test('grade reported in finding match', () {
      final s = ReadingLevelScanner(maxGrade: 3);
      final result = s.scan(complexText);
      expect(result.findings.first.match, contains('grade'));
    });

    test('output stage only', () {
      final s = ReadingLevelScanner();
      expect(s.stages, {ScanStage.output});
    });

    test('registry builds with config', () {
      final s = ScannerRegistry.instance.build('reading_level', {
        'minGrade': 3,
        'maxGrade': 12,
      });
      expect(s, isA<ReadingLevelScanner>());
    });

    test('simple text passes low max, complex does not', () {
      final s = ReadingLevelScanner(maxGrade: 6);
      expect(s.scan(simpleText).passed, isTrue);
      expect(s.scan(complexText).hasFindings, isTrue);
    });
  });
}
