import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/banned_topic_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('BannedTopicScanner', () {
    test('block: detects a single topic with correct offsets', () {
      final s = BannedTopicScanner(['weapons']);
      const text = 'buy weapons here';
      final r = s.scan(text);
      expect(r.passed, isFalse);
      expect(r.score, 1.0);
      expect(r.findings, hasLength(1));
      final f = r.findings.single;
      expect(f.type, 'topic.weapons');
      expect(text.substring(f.start, f.end), 'weapons');
      expect(r.reason, contains('weapons'));
      expect(r.text, text); // block leaves text unchanged
    });

    test('clean text passes with no findings', () {
      final s = BannedTopicScanner(['weapons', 'drugs']);
      final r = s.scan('a perfectly fine sentence');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
      expect(r.score, 0.0);
    });

    test('matches a multi-word phrase', () {
      final s = BannedTopicScanner(['gun control']);
      final r = s.scan('the gun control debate');
      expect(r.passed, isFalse);
      expect(r.findings.single.match, 'gun control');
    });

    test('case-insensitive by default', () {
      final s = BannedTopicScanner(['drugs']);
      final r = s.scan('DRUGS are banned');
      expect(r.passed, isFalse);
      expect(r.findings.single.match, 'DRUGS');
    });

    test('caseSensitive: true does not match a different case', () {
      final s = BannedTopicScanner(['drugs'], caseSensitive: true);
      final r = s.scan('DRUGS are banned');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('word boundary: substring does not match', () {
      final s = BannedTopicScanner(['cat']);
      final r = s.scan('the category is broad');
      expect(r.passed, isTrue);
      expect(r.hasFindings, isFalse);
    });

    test('redact: replaces matches with [TOPIC], passes', () {
      final s = BannedTopicScanner(['drugs'], action: GuardAction.redact);
      final r = s.scan('drugs and more drugs');
      expect(r.passed, isTrue);
      expect(r.text, '[TOPIC] and more [TOPIC]');
      expect(r.score, 0.5);
      expect(r.findings, hasLength(2));
      // findings keep offsets into the ORIGINAL text
      expect(
          'drugs and more drugs'
              .substring(r.findings.first.start, r.findings.first.end),
          'drugs');
    });

    test('hash: replaces matches with a stable [TOPIC:xxxxxx] token', () {
      final s = BannedTopicScanner(['drugs'], action: GuardAction.hash);
      final r1 = s.scan('drugs');
      final r2 = s.scan('drugs');
      expect(r1.passed, isTrue);
      expect(r1.text, matches(RegExp(r'^\[TOPIC:[0-9a-f]{6}\]$')));
      expect(r1.text, r2.text); // stable
    });

    test('warn: keeps findings, text unchanged, passes', () {
      final s = BannedTopicScanner(['drugs'], action: GuardAction.warn);
      const text = 'drugs here';
      final r = s.scan(text);
      expect(r.passed, isTrue);
      expect(r.text, text);
      expect(r.findings, hasLength(1));
      expect(r.score, 0.5);
    });

    test('reports multiple distinct topics', () {
      final s = BannedTopicScanner(['drugs', 'weapons']);
      final r = s.scan('drugs and weapons');
      expect(r.findings.map((f) => f.type),
          containsAll(['topic.drugs', 'topic.weapons']));
    });

    test('runs in both input and output stages', () {
      final s = BannedTopicScanner(['drugs']);
      expect(s.stages, containsAll([ScanStage.input, ScanStage.output]));
      expect(s.scan('drugs', stage: ScanStage.output).passed, isFalse);
    });
  });
}
