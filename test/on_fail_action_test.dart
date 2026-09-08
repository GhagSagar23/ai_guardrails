import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

/// Stub scanner that always blocks with findings.
class _BlockingScanner implements Scanner {
  @override
  final String name;
  final String? fix;
  _BlockingScanner(this.name, {this.fix});

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.block(name, text,
          findings: [Finding(type: '$name.issue')],
          reason: 'blocked by $name',
          suggestedFix: fix);
}

/// Stub scanner that warns (passes with findings).
class _WarningScanner implements Scanner {
  @override
  final String name;
  _WarningScanner(this.name);

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.warn(name, text,
          findings: [Finding(type: '$name.warning')],
          reason: 'warning from $name');
}

void main() {
  group('OnFailAction', () {
    test('parseOnFailAction parses all values', () {
      expect(parseOnFailAction('block'), OnFailAction.block);
      expect(parseOnFailAction('warn'), OnFailAction.warn);
      expect(parseOnFailAction('filter'), OnFailAction.filter);
      expect(parseOnFailAction('fix'), OnFailAction.fix);
      expect(parseOnFailAction('reask'), OnFailAction.reask);
      expect(parseOnFailAction('refrain'), OnFailAction.refrain);
      expect(parseOnFailAction('noop'), OnFailAction.noop);
    });

    test('parseOnFailAction returns null for null', () {
      expect(parseOnFailAction(null), isNull);
    });

    test('parseOnFailAction throws on unknown', () {
      expect(() => parseOnFailAction('unknown'), throwsArgumentError);
    });

    group('AiGuard integration', () {
      test('default: blocking scanner blocks pipeline', () async {
        final guard = AiGuard(inputScanners: [_BlockingScanner('test')]);
        final results = await guard.scanInput('hello');
        expect(results.last.passed, isFalse);
      });

      test('warn overrides block to warning', () async {
        final guard = AiGuard(
          inputScanners: [_BlockingScanner('test')],
          onFailActions: {'test': OnFailAction.warn},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'response',
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.inputResults.first.hasFindings, isTrue);
      });

      test('block escalates warning to block', () async {
        final guard = AiGuard(
          inputScanners: [_WarningScanner('test')],
          onFailActions: {'test': OnFailAction.block},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'response',
        );
        expect(outcome.blocked, isTrue);
        expect(outcome.failAction, OnFailAction.block);
      });

      test('filter clears text', () async {
        final guard = AiGuard(
          inputScanners: [
            _BlockingScanner('filter_me'),
            _WarningScanner('check'),
          ],
          onFailActions: {'filter_me': OnFailAction.filter},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => s,
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.input, isEmpty);
      });

      test('fix applies suggestedFix', () async {
        final guard = AiGuard(
          inputScanners: [_BlockingScanner('fixer', fix: 'fixed text')],
          onFailActions: {'fixer': OnFailAction.fix},
        );
        final outcome = await guard.run(
          input: 'bad input',
          llmCall: (s) async => s,
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.input, 'fixed text');
        expect(outcome.output, 'fixed text');
      });

      test('fix without suggestedFix keeps scanner text', () async {
        final guard = AiGuard(
          inputScanners: [_BlockingScanner('fixer')],
          onFailActions: {'fixer': OnFailAction.fix},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => s,
        );
        expect(outcome.blocked, isFalse);
      });

      test('refrain returns empty output, not blocked', () async {
        final guard = AiGuard(
          inputScanners: [_BlockingScanner('test')],
          onFailActions: {'test': OnFailAction.refrain},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'should not reach',
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.failAction, OnFailAction.refrain);
        expect(outcome.output, isEmpty);
      });

      test('reask treated as block in AiGuard.run', () async {
        final guard = AiGuard(
          outputScanners: [_BlockingScanner('test')],
          onFailActions: {'test': OnFailAction.reask},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'bad output',
        );
        expect(outcome.blocked, isTrue);
        expect(outcome.failAction, OnFailAction.reask);
      });

      test('noop skips scanner entirely', () async {
        final guard = AiGuard(
          inputScanners: [_BlockingScanner('skip_me')],
          onFailActions: {'skip_me': OnFailAction.noop},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'response',
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.inputResults, isEmpty);
      });

      test('multiple scanners with mixed actions', () async {
        final guard = AiGuard(
          inputScanners: [
            _BlockingScanner('s1'),
            _WarningScanner('s2'),
            _BlockingScanner('s3'),
          ],
          onFailActions: {
            's1': OnFailAction.warn,
            's3': OnFailAction.warn,
          },
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'response',
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.inputResults, hasLength(3));
      });

      test('fromConfig parses onFailActions', () async {
        final guard = AiGuard.fromConfig({
          'inputScanners': [
            {'type': 'token_limit', 'maxTokens': 2}
          ],
          'onFailActions': {'token_limit': 'warn'},
        });
        final outcome = await guard.run(
          input: 'this exceeds the tiny token limit quite a lot',
          llmCall: (s) async => 'ok',
        );
        expect(outcome.blocked, isFalse);
      });

      test('output stage refrain on output scanner', () async {
        final guard = AiGuard(
          outputScanners: [_BlockingScanner('test')],
          onFailActions: {'test': OnFailAction.refrain},
        );
        final outcome = await guard.run(
          input: 'hello',
          llmCall: (s) async => 'bad output',
        );
        expect(outcome.blocked, isFalse);
        expect(outcome.failAction, OnFailAction.refrain);
        expect(outcome.output, isEmpty);
        expect(outcome.blockedStage, ScanStage.output);
      });

      test('filter then next scanner sees empty text', () async {
        var secondSaw = '';
        final second = _SpyScanner('spy', (text) => secondSaw = text);
        final guard = AiGuard(
          inputScanners: [_BlockingScanner('first'), second],
          onFailActions: {'first': OnFailAction.filter},
        );
        await guard.scanInput('hello world');
        expect(secondSaw, isEmpty);
      });
    });
  });
}

class _SpyScanner implements Scanner {
  @override
  final String name;
  final void Function(String) onScan;
  _SpyScanner(this.name, this.onScan);

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    onScan(text);
    return ScanResult.pass(name, text);
  }
}
