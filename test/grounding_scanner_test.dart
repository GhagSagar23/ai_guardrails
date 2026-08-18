import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/grounding_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('GroundingScanner', () {
    const context = 'The Eiffel Tower is located in Paris, France. '
        'It was built in 1889 for the World Exposition. '
        'The tower stands 330 meters tall.';

    test('grounded output passes', () {
      final scanner = GroundingScanner(context: context);
      final r = scanner.scan('The Eiffel Tower in Paris is 330 meters tall.');
      expect(r.passed, isTrue);
    });

    test('ungrounded output with fabricated entities flags', () {
      final scanner = GroundingScanner(
        context: context,
        action: GuardAction.block,
      );
      final r = scanner.scan(
        'The Brandenburg Gate in Berlin was designed by Carl Langhans '
        'and completed in 1791 during the Prussian era.',
      );
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'grounding.unsupported_claim');
    });

    test('partially grounded output scores proportionally', () {
      final scanner = GroundingScanner(context: context, threshold: 0.8);
      final r = scanner.scan(
        'The Eiffel Tower in Paris was built by Gustave Eiffel '
        'using revolutionary iron lattice construction techniques.',
      );
      expect(r.score, greaterThan(0.0));
      expect(r.score, lessThan(1.0));
    });

    test('short output below minimum word count passes', () {
      final scanner = GroundingScanner(context: context);
      final r = scanner.scan('Yes.');
      expect(r.passed, isTrue);
    });

    test('block action blocks ungrounded output', () {
      final scanner = GroundingScanner(
        context: context,
        action: GuardAction.block,
      );
      final r = scanner.scan(
        'The Colosseum in Rome was built during the Flavian dynasty.',
      );
      expect(r.passed, isFalse);
    });

    test('warn action passes with findings', () {
      final scanner = GroundingScanner(context: context);
      final r = scanner.scan(
        'The Colosseum in Rome was built during the Flavian dynasty.',
      );
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
    });

    test('threshold adjusts sensitivity', () {
      const output = 'The Eiffel Tower was designed by architect Zaha Hadid.';
      final loose = GroundingScanner(
        context: context,
        threshold: 0.2,
        action: GuardAction.block,
      );
      final strict = GroundingScanner(
        context: context,
        threshold: 0.9,
        action: GuardAction.block,
      );
      expect(loose.scan(output).passed, isTrue);
      expect(strict.scan(output).passed, isFalse);
    });

    test('findings report ungrounded words', () {
      final scanner = GroundingScanner(context: context);
      final r = scanner.scan(
        'The Colosseum in Rome was built during the Flavian dynasty.',
      );
      final words = r.findings.map((f) => f.match).toSet();
      expect(words, contains('colosseum'));
      expect(words, contains('rome'));
    });

    test('reason includes percentage', () {
      final scanner = GroundingScanner(context: context);
      final r = scanner.scan(
        'The Colosseum in Rome was built during the Flavian dynasty.',
      );
      expect(r.reason, contains('grounded'));
      expect(r.reason, contains('%'));
    });

    test('scanner metadata', () {
      final scanner = GroundingScanner(context: context);
      expect(scanner.name, 'grounding');
      expect(scanner.stages, {ScanStage.output});
    });
  });
}
