import 'package:ai_guardrails/src/ai_guard.dart';
import 'package:ai_guardrails/src/scanner.dart';
import 'package:test/test.dart';

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

_FakeScanner _pass(String name) => _FakeScanner(
      name,
      const {ScanStage.input},
      (text, _) => ScanResult.pass(name, text),
    );

_FakeScanner _blockIfContains(String name, String needle) => _FakeScanner(
      name,
      const {ScanStage.input},
      (text, _) => text.contains(needle)
          ? ScanResult.block(name, text,
              findings: [Finding(type: '$name.hit')],
              reason: 'contains $needle')
          : ScanResult.pass(name, text),
    );

_FakeScanner _redactor(String name, String from, String to) => _FakeScanner(
      name,
      const {ScanStage.input},
      (text, _) => ScanResult(
        scanner: name,
        passed: true,
        text: text.replaceAll(from, to),
        findings:
            text.contains(from) ? [Finding(type: '$name.redact')] : const [],
        redactionMap: text.contains(from) ? {to: from} : const {},
      ),
    );

void main() {
  group('AiGuard.runRetrievalStage', () {
    test('all clean chunks pass through', () async {
      final guard = AiGuard(inputScanners: [_pass('noop')]);
      final result = await guard.runRetrievalStage(['a', 'b', 'c']);

      expect(result.accepted, ['a', 'b', 'c']);
      expect(result.dropped, isEmpty);
      expect(result.chunks.every((c) => c.passed), isTrue);
    });

    test('poisoned chunk is dropped, clean ones kept', () async {
      final guard = AiGuard(
        inputScanners: [_blockIfContains('inj', 'INJECT')],
      );
      final result = await guard.runRetrievalStage([
        'safe doc',
        'has INJECT payload',
        'also safe',
      ]);

      expect(result.accepted, ['safe doc', 'also safe']);
      expect(result.dropped, hasLength(1));
      expect(result.dropped.first.index, 1);
      expect(result.dropped.first.dropReason, contains('INJECT'));
    });

    test('chunks are scanned independently — one block does not stop others',
        () async {
      final guard = AiGuard(
        inputScanners: [_blockIfContains('sec', 'SECRET')],
      );
      final result = await guard.runRetrievalStage([
        'SECRET in first',
        'clean second',
        'SECRET in third',
        'clean fourth',
      ]);

      expect(result.accepted, ['clean second', 'clean fourth']);
      expect(result.dropped, hasLength(2));
      expect(result.dropped.map((c) => c.index), [0, 2]);
    });

    test('empty chunk list returns empty result', () async {
      final guard = AiGuard(inputScanners: [_pass('noop')]);
      final result = await guard.runRetrievalStage([]);

      expect(result.chunks, isEmpty);
      expect(result.accepted, isEmpty);
      expect(result.dropped, isEmpty);
      expect(result.allFindings, isEmpty);
    });

    test('redaction chains work per-chunk', () async {
      final guard = AiGuard(
        inputScanners: [_redactor('pii', 'alice@test.com', '[EMAIL_1]')],
      );
      final result = await guard.runRetrievalStage([
        'contact alice@test.com here',
        'no pii here',
      ]);

      expect(result.accepted, [
        'contact [EMAIL_1] here',
        'no pii here',
      ]);
      expect(result.chunks[0].processedChunk, 'contact [EMAIL_1] here');
      expect(result.chunks[0].originalChunk, 'contact alice@test.com here');
      expect(result.chunks[1].results.first.findings, isEmpty);
    });

    test('allFindings aggregates across all chunks', () async {
      final guard = AiGuard(
        inputScanners: [_redactor('pii', 'secret', '[REDACTED]')],
      );
      final result = await guard.runRetrievalStage([
        'has secret',
        'clean',
        'another secret here',
      ]);

      expect(result.allFindings, hasLength(2));
      expect(result.allFindings.every((f) => f.type == 'pii.redact'), isTrue);
    });

    test('failClosed=true blocks chunk when scanner throws', () async {
      final throwing = _FakeScanner(
        'bad',
        const {ScanStage.input},
        (_, __) => throw StateError('boom'),
      );
      final guard = AiGuard(inputScanners: [throwing], failClosed: true);
      final result = await guard.runRetrievalStage(['anything']);

      expect(result.accepted, isEmpty);
      expect(result.dropped, hasLength(1));
      expect(result.dropped.first.dropReason, contains('scanner error'));
    });

    test('failClosed=false skips throwing scanner, chunk passes', () async {
      final throwing = _FakeScanner(
        'bad',
        const {ScanStage.input},
        (_, __) => throw StateError('boom'),
      );
      final guard = AiGuard(inputScanners: [throwing], failClosed: false);
      final result = await guard.runRetrievalStage(['anything']);

      expect(result.accepted, ['anything']);
      expect(result.dropped, isEmpty);
    });

    test('output-only scanners are skipped during retrieval', () async {
      final outputOnly = _FakeScanner(
        'out',
        const {ScanStage.output},
        (text, _) => ScanResult.block('out', text,
            findings: [Finding(type: 'out.hit')], reason: 'output only'),
      );
      final guard = AiGuard(inputScanners: [outputOnly]);
      final result = await guard.runRetrievalStage(['should pass']);

      expect(result.accepted, ['should pass']);
    });

    test('preserves chunk order in results', () async {
      final guard = AiGuard(inputScanners: [_pass('noop')]);
      final chunks = List.generate(10, (i) => 'chunk_$i');
      final result = await guard.runRetrievalStage(chunks);

      for (var i = 0; i < 10; i++) {
        expect(result.chunks[i].index, i);
        expect(result.chunks[i].originalChunk, 'chunk_$i');
      }
    });
  });
}
