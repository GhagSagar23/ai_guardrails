import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('PaddingAttackScanner', () {
    late PaddingAttackScanner scanner;

    setUp(() {
      scanner = PaddingAttackScanner();
    });

    test('clean text passes', () {
      final r = scanner.scan(
        'The quick brown fox jumps over the lazy dog. '
        'This is a normal sentence with reasonable entropy.',
      );
      expect(r.passed, isTrue);
      expect(r.findings, isEmpty);
    });

    test('low entropy padding detected', () {
      // Repeated single character — very low entropy
      final r = scanner.scan('a' * 200);
      expect(r.passed, isFalse);
      expect(r.findings, isNotEmpty);
      expect(r.findings.any((f) => f.type == 'padding.low_entropy'), isTrue);
    });

    test('single-char run detected', () {
      // Text with long runs of same character
      final padding = 'x' * 50;
      final text = 'Normal start. $padding Then more text follows here. '
          '$padding And even more content after padding.';
      final r = scanner.scan(text);
      expect(r.findings.any((f) => f.type == 'padding.char_run'), isTrue);
    });

    test('short text skipped', () {
      final r = scanner.scan('short');
      expect(r.passed, isTrue);
    });

    test('empty text skipped', () {
      final r = scanner.scan('');
      expect(r.passed, isTrue);
    });

    test('configurable entropy floor', () {
      // Very low floor — most text passes
      final lenient = PaddingAttackScanner(entropyFloor: 0.5);
      final r = lenient.scan('aababababababababababababababababababababab');
      expect(r.passed, isTrue);
    });

    test('configurable run ratio', () {
      // Strict ratio — catches smaller runs
      final strict = PaddingAttackScanner(maxRunRatio: 0.01);
      final text = 'Hello world. ${'z' * 10} End of message here.';
      final r = strict.scan(text);
      expect(r.findings.any((f) => f.type == 'padding.char_run'), isTrue);
    });

    test('configurable min run length', () {
      // Only count runs of 10+ as suspicious
      final s = PaddingAttackScanner(minRunLength: 10);
      final text = 'Hello ${'a' * 8} world ${'b' * 8} end of test here.';
      final r = s.scan(text);
      // Runs of 8 shouldn't count with minRunLength=10
      expect(r.findings.where((f) => f.type == 'padding.char_run'), isEmpty);
    });

    test('warn action does not block', () {
      final s = PaddingAttackScanner(action: GuardAction.warn);
      final r = s.scan('a' * 200);
      expect(r.passed, isTrue);
      expect(r.findings, isNotEmpty);
    });

    test('input stage only', () {
      expect(scanner.stages, contains(ScanStage.input));
      expect(scanner.stages, isNot(contains(ScanStage.output)));
    });

    test('name is padding_attack', () {
      expect(scanner.name, 'padding_attack');
    });

    test('mixed content with some padding passes if under threshold', () {
      // Mostly normal text with a small run
      final text = 'This is a perfectly normal paragraph with good entropy. '
          'It contains varied characters and word patterns. '
          '${'x' * 5} '
          'And then continues with more normal writing.';
      final r = scanner.scan(text);
      expect(r.passed, isTrue);
    });

    test('binary-like random text has high entropy', () {
      // Simulated high-entropy text
      final chars = List.generate(
          200, (i) => String.fromCharCode(33 + (i * 7 + i * i) % 94));
      final text = chars.join();
      final r = scanner.scan(text);
      expect(r.findings.where((f) => f.type == 'padding.low_entropy'), isEmpty);
    });

    test('confidence scales with severity', () {
      final r = scanner.scan('a' * 200);
      final lowEntropy =
          r.findings.firstWhere((f) => f.type == 'padding.low_entropy');
      expect(lowEntropy.confidence, greaterThan(0.5));
    });

    test('registry builds padding_attack scanner', () {
      final reg = ScannerRegistry.instance;
      expect(reg.has('padding_attack'), isTrue);
      final s = reg.build('padding_attack', {'entropyFloor': 2.0});
      expect(s, isA<PaddingAttackScanner>());
    });

    test('fromConfig builds padding_attack', () {
      final guard = AiGuard.fromConfig({
        'inputScanners': [
          {'type': 'padding_attack', 'entropyFloor': 2.5, 'maxRunRatio': 0.05},
        ],
      });
      expect(guard.inputScanners, hasLength(1));
      expect(guard.inputScanners.first, isA<PaddingAttackScanner>());
    });

    test('detects space padding', () {
      final r = scanner.scan(' ' * 200);
      expect(r.passed, isFalse);
    });

    test('detects null byte style padding', () {
      final r = scanner.scan('\x00' * 200);
      expect(r.passed, isFalse);
    });
  });
}
