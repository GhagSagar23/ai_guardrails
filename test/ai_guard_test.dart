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
  });
}
