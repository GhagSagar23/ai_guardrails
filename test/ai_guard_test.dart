import 'package:ai_guardrails/src/ai_guard.dart';
import 'package:ai_guardrails/src/scanner.dart';
import 'package:test/test.dart';

/// A configurable fake scanner: behavior is a closure so one class covers
/// block / redact / pass-with-findings cases.
class _FakeScanner implements Scanner {
  @override
  final String name;
  @override
  final Set<ScanStage> stages;
  final ScanResult Function(String text, ScanStage stage) _fn;

  _FakeScanner(this.name, this.stages, this._fn);

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      _fn(text, stage);
}

/// A scanner that always throws, to exercise failClosed.
class _ThrowingScanner implements Scanner {
  @override
  String get name => 'throwing';
  @override
  Set<ScanStage> get stages => const {ScanStage.input};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      throw StateError('boom');
}

_FakeScanner _blocker(String name, Set<ScanStage> stages) => _FakeScanner(
      name,
      stages,
      (text, stage) => ScanResult(
        scanner: name,
        passed: false,
        text: text,
        score: 1.0,
        findings: [Finding(type: '$name.hit')],
        reason: '$name blocked',
      ),
    );

void main() {
  group('AiGuard.run', () {
    test('input block short-circuits: llmCall is never invoked', () async {
      var called = false;
      final guard = AiGuard(
        inputScanners: [
          _blocker('in', const {ScanStage.input})
        ],
      );
      final outcome = await guard.run(
        input: 'anything',
        llmCall: (s) async {
          called = true;
          return 'response';
        },
      );
      expect(called, isFalse);
      expect(outcome.blocked, isTrue);
      expect(outcome.blockedStage, ScanStage.input);
      expect(outcome.blockReason, 'in blocked');
      expect(outcome.output, isNull);
    });

    test('redacting input scanner chains transformed text into llmCall',
        () async {
      String? seenByLlm;
      final redactor = _FakeScanner(
        'redact',
        const {ScanStage.input},
        (text, stage) => ScanResult(
          scanner: 'redact',
          passed: true,
          text: text.replaceAll('foo', 'bar'),
          score: 0.5,
          findings: [Finding(type: 'redact.hit')],
        ),
      );
      final guard = AiGuard(inputScanners: [redactor]);
      final outcome = await guard.run(
        input: 'foo baz foo',
        llmCall: (s) async {
          seenByLlm = s;
          return 'ok';
        },
      );
      expect(seenByLlm, 'bar baz bar');
      expect(outcome.input, 'bar baz bar');
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'ok');
    });

    test('output block fires after the LLM has run', () async {
      var called = false;
      final guard = AiGuard(
        outputScanners: [
          _blocker('out', const {ScanStage.output})
        ],
      );
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async {
          called = true;
          return 'leaky response';
        },
      );
      expect(called, isTrue);
      expect(outcome.blocked, isTrue);
      expect(outcome.blockedStage, ScanStage.output);
      expect(outcome.blockReason, 'out blocked');
    });

    test('failClosed=true turns a throwing scanner into a block', () async {
      var called = false;
      final guard = AiGuard(
        inputScanners: [_ThrowingScanner()],
        failClosed: true,
      );
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async {
          called = true;
          return 'x';
        },
      );
      expect(called, isFalse);
      expect(outcome.blocked, isTrue);
      expect(outcome.blockedStage, ScanStage.input);
      expect(outcome.blockReason, contains('scanner error'));
    });

    test('failClosed=false skips a throwing scanner', () async {
      var called = false;
      final guard = AiGuard(
        inputScanners: [_ThrowingScanner()],
        failClosed: false,
      );
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async {
          called = true;
          return 'x';
        },
      );
      expect(called, isTrue);
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'x');
    });

    test('allFindings aggregates input and output pipelines', () async {
      final inFinder = _FakeScanner(
        'inf',
        const {ScanStage.input},
        (text, stage) => ScanResult(
          scanner: 'inf',
          passed: true,
          text: text,
          score: 0.5,
          findings: [Finding(type: 'inf.a')],
        ),
      );
      final outFinder = _FakeScanner(
        'outf',
        const {ScanStage.output},
        (text, stage) => ScanResult(
          scanner: 'outf',
          passed: true,
          text: text,
          score: 0.5,
          findings: [Finding(type: 'outf.b')],
        ),
      );
      final guard = AiGuard(
        inputScanners: [inFinder],
        outputScanners: [outFinder],
      );
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async => 'resp',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.allFindings.map((f) => f.type),
          containsAll(['inf.a', 'outf.b']));
      expect(outcome.allFindings, hasLength(2));
    });

    test('PII round-trip: output is rehydrated with original values', () async {
      final redactor = _FakeScanner(
        'redact',
        const {ScanStage.input},
        (text, stage) => ScanResult(
          scanner: 'redact',
          passed: true,
          text: text.replaceAll('alice@example.com', '[EMAIL_1]'),
          score: 0.5,
          findings: [Finding(type: 'pii.email', match: 'alice@example.com')],
          redactionMap: const {'[EMAIL_1]': 'alice@example.com'},
        ),
      );
      final guard = AiGuard(inputScanners: [redactor]);
      final outcome = await guard.run(
        input: 'contact alice@example.com please',
        llmCall: (s) async => 'Sure, I emailed [EMAIL_1] for you.',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'Sure, I emailed alice@example.com for you.');
      expect(outcome.rawOutput, 'Sure, I emailed [EMAIL_1] for you.');
      expect(outcome.piiMap, {'[EMAIL_1]': 'alice@example.com'});
      expect(outcome.input, 'contact [EMAIL_1] please');
    });

    test('piiMap is empty when no redaction occurred', () async {
      final guard = AiGuard();
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async => 'hello',
      );
      expect(outcome.piiMap, isEmpty);
      expect(outcome.output, 'hello');
      expect(outcome.rawOutput, 'hello');
    });

    test('multiple redaction maps merge across scanners', () async {
      final s1 = _FakeScanner(
        's1',
        const {ScanStage.input},
        (text, stage) => ScanResult(
          scanner: 's1',
          passed: true,
          text: text.replaceAll('secret1', '[S1]'),
          score: 0.5,
          findings: [Finding(type: 's1.hit')],
          redactionMap: const {'[S1]': 'secret1'},
        ),
      );
      final s2 = _FakeScanner(
        's2',
        const {ScanStage.input},
        (text, stage) => ScanResult(
          scanner: 's2',
          passed: true,
          text: text.replaceAll('secret2', '[S2]'),
          score: 0.5,
          findings: [Finding(type: 's2.hit')],
          redactionMap: const {'[S2]': 'secret2'},
        ),
      );
      final guard = AiGuard(inputScanners: [s1, s2]);
      final outcome = await guard.run(
        input: 'secret1 and secret2',
        llmCall: (s) async => 'got [S1] and [S2]',
      );
      expect(outcome.output, 'got secret1 and secret2');
      expect(outcome.piiMap, {'[S1]': 'secret1', '[S2]': 'secret2'});
    });
  });
}
