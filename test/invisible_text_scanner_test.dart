import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/invisible_text_scanner.dart';
import 'package:test/test.dart';

// Built from code points so the source stays free of literal invisibles.
final zeroWidth = String.fromCharCode(0x200B); // ZERO WIDTH SPACE
final bidi = String.fromCharCode(0x202E); // RIGHT-TO-LEFT OVERRIDE
final softHyphen = String.fromCharCode(0x00AD); // SOFT HYPHEN
final tag = String.fromCharCode(0xE0041); // TAG LATIN CAPITAL A (astral)

void main() {
  group('InvisibleTextScanner detection by category', () {
    const scanner = InvisibleTextScanner();

    test('zero-width is detected', () {
      final r = scanner.scan('a${zeroWidth}b');
      expect(r.findings.single.type, 'invisible.zero_width');
    });

    test('bidi control is detected', () {
      final r = scanner.scan('a${bidi}b');
      expect(r.findings.single.type, 'invisible.bidi');
    });

    test('soft hyphen is detected', () {
      final r = scanner.scan('a${softHyphen}b');
      expect(r.findings.single.type, 'invisible.soft_hyphen');
    });

    test('astral tag char is detected with a 2-unit span', () {
      const scanner = InvisibleTextScanner();
      final r = scanner.scan('x${tag}y');
      final f = r.findings.single;
      expect(f.type, 'invisible.tag');
      expect(f.end - f.start, 2); // surrogate pair
    });

    test('multiple categories in one string all detected', () {
      final r = scanner.scan('$zeroWidth$bidi$softHyphen');
      expect(
          r.findings.map((f) => f.type),
          containsAll([
            'invisible.zero_width',
            'invisible.bidi',
            'invisible.soft_hyphen',
          ]));
    });
  });

  test('clean text passes with no findings', () {
    final r = const InvisibleTextScanner().scan('hello world');
    expect(r.passed, isTrue);
    expect(r.hasFindings, isFalse);
    expect(r.score, 0.0);
    expect(r.text, 'hello world');
  });

  group('InvisibleTextScanner GuardAction paths', () {
    final dirty = 'a${zeroWidth}b${softHyphen}c';

    test('redact (default) strips invisibles and passes', () {
      final r = const InvisibleTextScanner().scan(dirty);
      expect(r.passed, isTrue);
      expect(r.text, 'abc');
      expect(r.findings, hasLength(2));
    });

    test('redact strips an astral tag char too', () {
      final r = const InvisibleTextScanner().scan('x${tag}y');
      expect(r.text, 'xy');
    });

    test('block rejects with a non-zero score', () {
      final r =
          const InvisibleTextScanner(action: GuardAction.block).scan(dirty);
      expect(r.passed, isFalse);
      expect(r.score, greaterThan(0.0));
      expect(r.text, dirty); // text unchanged on block
    });

    test('warn keeps findings, passes, leaves text unchanged', () {
      final r =
          const InvisibleTextScanner(action: GuardAction.warn).scan(dirty);
      expect(r.passed, isTrue);
      expect(r.hasFindings, isTrue);
      expect(r.text, dirty);
    });

    test('hash tokenizes invisibles stably and passes', () {
      const s = InvisibleTextScanner(action: GuardAction.hash);
      final a = s.scan('a${zeroWidth}b');
      final b = s.scan('a${zeroWidth}b');
      expect(a.passed, isTrue);
      expect(a.text, contains('[zero_width:'));
      expect(a.text, b.text); // stable
    });
  });

  test('stages is input-only and name is stable', () {
    const s = InvisibleTextScanner();
    expect(s.name, 'invisible_text');
    expect(s.stages, {ScanStage.input});
  });
}
