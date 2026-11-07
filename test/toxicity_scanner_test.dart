import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('ToxicityScanner', () {
    final s = ToxicityScanner();

    test('clean text passes', () {
      expect(s.scan('The weather is lovely today.').passed, isTrue);
    });

    test('empty text passes', () {
      expect(s.scan('').passed, isTrue);
    });

    test('name and stages', () {
      expect(s.name, 'toxicity');
      expect(s.stages, {ScanStage.input, ScanStage.output});
    });

    final samples = {
      ToxCategory.toxicity: 'Fuck you, you piece of shit.',
      ToxCategory.harassment: 'I will find you. Go die, you deserve to suffer.',
      ToxCategory.hate: 'Those people should be exterminated, subhuman vermin.',
      ToxCategory.selfHarm: 'I want to die and kill myself, end my life.',
      ToxCategory.sexual: 'Send explicit sex tape and nude pics, porn.',
      ToxCategory.violence: 'I will kill you and slit your throat.',
    };
    for (final e in samples.entries) {
      test('detects ${e.key.name}', () {
        final r = ToxicityScanner(categories: {e.key}).scan(e.value);
        expect(r.passed, isFalse);
        expect(r.findings, isNotEmpty);
        expect(r.findings.every((f) => f.type == 'toxicity.${e.key.name}'),
            isTrue);
      });
    }

    test('detects leet-speak evasion', () {
      final r = s.scan('I will k1ll you and sl1t your throat');
      expect(r.passed, isFalse);
    });

    test('case insensitive', () {
      expect(s.scan('I WILL KILL YOU').passed, isFalse);
    });

    test('finding carries match text and offsets', () {
      const text = 'hello. I will kill you';
      final f = s.scan(text).findings.first;
      expect(f.match!.toLowerCase(), 'kill you');
      expect(text.substring(f.start, f.end), f.match);
    });

    test('score is within 0..1', () {
      final r = s.scan(samples.values.join(' '));
      expect(r.score, inInclusiveRange(0.0, 1.0));
      expect(r.score, greaterThan(0.0));
    });

    test('multiple categories triggered at once', () {
      final r = s.scan('I will kill you. Go die. I want to die.');
      final types = r.findings.map((f) => f.type).toSet();
      expect(types, containsAll(['toxicity.violence', 'toxicity.harassment']));
      expect(types, contains('toxicity.selfHarm'));
    });

    test('high threshold passes mild content', () {
      const mild = 'You are such an idiot.';
      expect(ToxicityScanner(threshold: 0.3).scan(mild).passed, isFalse);
      expect(ToxicityScanner(threshold: 0.7).scan(mild).passed, isTrue);
    });

    test('category subset ignores other categories', () {
      final only = ToxicityScanner(categories: {ToxCategory.sexual});
      expect(only.scan('I will kill you').passed, isTrue);
      expect(only.scan('explicit sex tape').passed, isFalse);
    });

    test('action block vs warn', () {
      final blocked = s.scan('I will kill you');
      expect(blocked.passed, isFalse);
      final warned =
          ToxicityScanner(action: GuardAction.warn).scan('I will kill you');
      expect(warned.passed, isTrue);
      expect(warned.hasFindings, isTrue);
    });

    test('works on input and output stages', () {
      expect(s.scan('I will kill you', stage: ScanStage.input).passed, isFalse);
      expect(
          s.scan('I will kill you', stage: ScanStage.output).passed, isFalse);
    });

    test('registry builds from config', () {
      final built = ScannerRegistry.instance.build('toxicity', {
        'threshold': 0.5,
        'action': 'warn',
        'categories': ['violence'],
      }) as ToxicityScanner;
      expect(built.threshold, 0.5);
      expect(built.action, GuardAction.warn);
      expect(built.categories, {ToxCategory.violence});
    });
  });
}
