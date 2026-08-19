import 'package:ai_guardrails/src/scanner.dart';
import 'package:ai_guardrails/src/scanners/pii_scanner.dart';
import 'package:ai_guardrails/src/streaming_ai_guard.dart';
import 'package:test/test.dart';

/// A fake scanner that blocks text containing a trigger word.
class _BlockOnWord implements Scanner {
  final String trigger;
  _BlockOnWord(this.trigger);
  @override
  String get name => 'block_on_word';
  @override
  Set<ScanStage> get stages => const {ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    if (text.contains(trigger)) {
      return ScanResult(
        scanner: name,
        passed: false,
        text: text,
        score: 1.0,
        findings: [Finding(type: 'block.trigger', match: trigger)],
        reason: 'blocked: $trigger',
      );
    }
    return ScanResult.pass(name, text);
  }
}

/// A fake scanner that blocks on input stage.
class _InputBlocker implements Scanner {
  @override
  String get name => 'input_blocker';
  @override
  Set<ScanStage> get stages => const {ScanStage.input};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult(
        scanner: name,
        passed: false,
        text: text,
        score: 1.0,
        reason: 'input blocked',
      );
}

Stream<String> _streamFrom(List<String> chunks) => Stream.fromIterable(chunks);

void main() {
  group('StreamingAiGuard', () {
    test('clean stream yields all segments', () async {
      final guard = StreamingAiGuard();
      final chunks = await guard
          .run(
            input: 'hello',
            llmStream: (_) => _streamFrom(['Line one\n', 'Line two\n']),
          )
          .toList();
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.every((c) => !c.blocked), isTrue);
      final text = chunks.map((c) => c.text).join();
      expect(text, contains('Line one'));
      expect(text, contains('Line two'));
    });

    test('input block yields blocked chunk and stops', () async {
      final guard = StreamingAiGuard(
        inputScanners: [_InputBlocker()],
      );
      var streamCalled = false;
      final chunks = await guard
          .run(
            input: 'anything',
            llmStream: (_) {
              streamCalled = true;
              return _streamFrom(['should not appear']);
            },
          )
          .toList();
      expect(streamCalled, isFalse);
      expect(chunks, hasLength(1));
      expect(chunks.first.blocked, isTrue);
    });

    test('output block terminates the stream', () async {
      final guard = StreamingAiGuard(
        outputScanners: [_BlockOnWord('DANGER')],
      );
      final chunks = await guard
          .run(
            input: 'hi',
            llmStream: (_) => _streamFrom([
              'Safe line\n',
              'DANGER ahead\n',
              'Should not appear\n',
            ]),
          )
          .toList();
      final blocked = chunks.where((c) => c.blocked);
      expect(blocked, hasLength(1));
      expect(blocked.first.blockReason, contains('DANGER'));
      final afterBlock = chunks.skipWhile((c) => !c.blocked).skip(1).toList();
      expect(afterBlock, isEmpty);
    });

    test('PII rehydration works in streaming mode', () async {
      final guard = StreamingAiGuard(
        inputScanners: [
          PiiScanner(action: GuardAction.redact, types: {'email'})
        ],
      );
      String? sanitizedInput;
      final chunks = await guard
          .run(
            input: 'Contact alice@example.com please',
            llmStream: (s) {
              sanitizedInput = s;
              return _streamFrom(['Emailed [EMAIL_1] done\n']);
            },
          )
          .toList();
      expect(sanitizedInput, contains('[EMAIL_1]'));
      expect(sanitizedInput, isNot(contains('alice@example.com')));
      final text = chunks.map((c) => c.text).join();
      expect(text, contains('alice@example.com'));
    });

    test('remaining buffer is flushed after stream ends', () async {
      final guard = StreamingAiGuard();
      final chunks = await guard
          .run(
            input: 'hi',
            llmStream: (_) => _streamFrom(['no trailing newline']),
          )
          .toList();
      expect(chunks, isNotEmpty);
      final text = chunks.map((c) => c.text).join();
      expect(text, contains('no trailing newline'));
    });

    test('custom boundary splits at sentence ends', () async {
      final guard = StreamingAiGuard(
        boundary: RegExp(r'(?<=[.!?])\s'),
      );
      final chunks = await guard
          .run(
            input: 'hi',
            llmStream: (_) =>
                _streamFrom(['First sentence. Second sentence. ']),
          )
          .toList();
      expect(chunks.length, greaterThanOrEqualTo(1));
    });

    test('scanInput delegates to AiGuard', () {
      final guard = StreamingAiGuard(
        inputScanners: [
          PiiScanner(action: GuardAction.warn, types: {'email'})
        ],
      );
      final results = guard.scanInput('test alice@example.com');
      expect(results.any((r) => r.hasFindings), isTrue);
    });
  });
}
