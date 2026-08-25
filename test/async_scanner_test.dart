import 'package:ai_guardrails/src/ai_guard.dart';
import 'package:ai_guardrails/src/scanner.dart';
import 'package:test/test.dart';

/// A configurable fake async scanner: behavior is a closure so one class
/// covers pass / block / throw cases.
class _TestAsyncScanner extends AsyncScanner {
  @override
  final String name;
  @override
  final Set<ScanStage> stages;
  final Future<ScanResult> Function(String text, ScanStage stage) _fn;

  _TestAsyncScanner(this.name, this.stages, this._fn);

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    await Future.delayed(const Duration(milliseconds: 1));
    return _fn(text, stage);
  }
}

void main() {
  group('AsyncScanner', () {
    test('async scanner passes in input pipeline', () async {
      final scanner = _TestAsyncScanner(
        'async_pass',
        const {ScanStage.input},
        (text, stage) async => ScanResult.pass('async_pass', text),
      );
      final guard = AiGuard(inputScanners: [scanner]);
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async => 'ok',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'ok');
    });

    test('async scanner blocks in input pipeline', () async {
      var called = false;
      final scanner = _TestAsyncScanner(
        'async_block',
        const {ScanStage.input},
        (text, stage) async => ScanResult(
          scanner: 'async_block',
          passed: false,
          text: text,
          score: 1.0,
          reason: 'async blocked',
        ),
      );
      final guard = AiGuard(inputScanners: [scanner]);
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async {
          called = true;
          return 'ok';
        },
      );
      expect(called, isFalse);
      expect(outcome.blocked, isTrue);
      expect(outcome.blockedStage, ScanStage.input);
      expect(outcome.blockReason, 'async blocked');
    });

    test('async scanner works in output pipeline', () async {
      final scanner = _TestAsyncScanner(
        'async_output',
        const {ScanStage.output},
        (text, stage) async => ScanResult(
          scanner: 'async_output',
          passed: true,
          text: text,
          findings: [Finding(type: 'async_output.hit')],
        ),
      );
      final guard = AiGuard(outputScanners: [scanner]);
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async => 'response text',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.outputResults, hasLength(1));
      expect(outcome.outputResults.single.findings.single.type,
          'async_output.hit');
    });

    test('mixed sync and async scanners preserve order', () async {
      String? seenByAsync;
      final syncRedactor = _OrderingSyncScanner();
      final asyncScanner = _TestAsyncScanner(
        'async_seer',
        const {ScanStage.input},
        (text, stage) async {
          seenByAsync = text;
          return ScanResult.pass('async_seer', text);
        },
      );
      final guard = AiGuard(inputScanners: [syncRedactor, asyncScanner]);
      final outcome = await guard.run(
        input: 'foo baz',
        llmCall: (s) async => s,
      );
      expect(seenByAsync, 'bar baz');
      expect(outcome.input, 'bar baz');
    });

    test('failClosed works with async scanner that throws', () async {
      var called = false;
      final scanner = _TestAsyncScanner(
        'async_throws',
        const {ScanStage.input},
        (text, stage) async => throw StateError('boom'),
      );
      final guard = AiGuard(
        inputScanners: [scanner],
        failClosed: true,
      );
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async {
          called = true;
          return 'ok';
        },
      );
      expect(called, isFalse);
      expect(outcome.blocked, isTrue);
      expect(outcome.blockReason, contains('scanner error'));
    });

    test('chains two async scanners back-to-back', () async {
      String? seenBySecond;
      final first = _TestAsyncScanner(
        'async_first',
        const {ScanStage.input},
        (text, stage) async =>
            ScanResult.pass('async_first', text.replaceAll('foo', 'bar')),
      );
      final second = _TestAsyncScanner(
        'async_second',
        const {ScanStage.input},
        (text, stage) async {
          seenBySecond = text;
          return ScanResult(
            scanner: 'async_second',
            passed: true,
            text: text,
            findings: [Finding(type: 'async_second.hit')],
          );
        },
      );
      final guard = AiGuard(inputScanners: [first, second]);
      final outcome = await guard.run(
        input: 'foo baz',
        llmCall: (s) async => s,
      );
      expect(seenBySecond, 'bar baz');
      expect(outcome.input, 'bar baz');
      expect(outcome.inputResults, hasLength(2));
      expect(outcome.inputResults[0].scanner, 'async_first');
      expect(outcome.inputResults[1].scanner, 'async_second');
      expect(outcome.inputResults[1].findings.single.type, 'async_second.hit');
    });

    test('failClosed=false skips throwing async scanner', () async {
      var called = false;
      final scanner = _TestAsyncScanner(
        'async_throws',
        const {ScanStage.input},
        (text, stage) async => throw StateError('boom'),
      );
      final guard = AiGuard(
        inputScanners: [scanner],
        failClosed: false,
      );
      final outcome = await guard.run(
        input: 'hi',
        llmCall: (s) async {
          called = true;
          return 'ok';
        },
      );
      expect(called, isTrue);
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'ok');
    });
  });
}

/// A sync scanner that redacts "foo" -> "bar", used to verify pipeline order.
class _OrderingSyncScanner implements Scanner {
  @override
  String get name => 'ordering_sync';
  @override
  Set<ScanStage> get stages => const {ScanStage.input};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult(
        scanner: name,
        passed: true,
        text: text.replaceAll('foo', 'bar'),
      );
}
