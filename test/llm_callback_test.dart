import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

/// Test scanner that mixes in [LlmDependent] to verify injection.
class _FakeLlmScanner extends AsyncScanner with LlmDependent {
  @override
  String get name => 'fake_llm';

  @override
  Set<ScanStage> get stages => {ScanStage.input, ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    final judgment = await llmCallback('Is this safe? $text');
    if (judgment == 'unsafe') {
      return ScanResult.block(name, text,
          findings: [Finding(type: 'llm.unsafe')], reason: 'LLM said unsafe');
    }
    return ScanResult.pass(name, text);
  }
}

/// Plain scanner with no LLM dependency.
class _PlainScanner extends Scanner {
  @override
  String get name => 'plain';

  @override
  Set<ScanStage> get stages => {ScanStage.input};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.pass(name, text);
}

void main() {
  group('LlmCallback injection', () {
    test('AiGuard accepts llmCallback without LlmDependent scanners', () {
      final guard = AiGuard(
        inputScanners: [_PlainScanner()],
        llmCallback: (p) async => 'ok',
      );
      expect(guard.llmCallback, isNotNull);
    });

    test('AiGuard works without llmCallback when no LlmDependent scanners', () {
      final guard = AiGuard(inputScanners: [_PlainScanner()]);
      expect(guard.llmCallback, isNull);
    });

    test('AiGuard throws when LlmDependent scanner present but no callback',
        () {
      expect(
        () => AiGuard(inputScanners: [_FakeLlmScanner()]),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('fake_llm requires llmCallback'),
        )),
      );
    });

    test('AiGuard throws for LlmDependent in outputScanners too', () {
      expect(
        () => AiGuard(outputScanners: [_FakeLlmScanner()]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('LlmDependent scanner receives the callback and can use it', () async {
      final guard = AiGuard(
        inputScanners: [_FakeLlmScanner()],
        llmCallback: (prompt) async => 'safe',
      );
      final results = await guard.scanInput('hello');
      expect(results.single.passed, isTrue);
    });

    test('LlmDependent scanner blocks when LLM says unsafe', () async {
      final guard = AiGuard(
        inputScanners: [_FakeLlmScanner()],
        llmCallback: (prompt) async => 'unsafe',
      );
      final results = await guard.scanInput('bad stuff');
      expect(results.single.passed, isFalse);
      expect(results.single.findings.single.type, 'llm.unsafe');
    });

    test('llmCallback getter throws StateError when not injected', () {
      final scanner = _FakeLlmScanner();
      expect(() => scanner.llmCallback, throwsStateError);
    });

    test('fromConfig threads llmCallback', () {
      final guard = AiGuard.fromConfig(
        {'inputScanners': []},
        llmCallback: (p) async => 'ok',
      );
      expect(guard.llmCallback, isNotNull);
    });

    test('StreamingAiGuard threads llmCallback to inner AiGuard', () {
      // Doesn't throw — proves the callback reached the LlmDependent scanner.
      final streaming = StreamingAiGuard(
        inputScanners: [_FakeLlmScanner()],
        llmCallback: (p) async => 'safe',
      );
      expect(streaming, isNotNull);
    });

    test('StreamingAiGuard throws without callback for LlmDependent scanner',
        () {
      expect(
        () => StreamingAiGuard(inputScanners: [_FakeLlmScanner()]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('full run() round-trip with LlmDependent scanner', () async {
      final guard = AiGuard(
        inputScanners: [_FakeLlmScanner()],
        llmCallback: (prompt) async => 'safe',
      );
      final outcome = await guard.run(
        input: 'hello',
        llmCall: (sanitized) async => 'response to $sanitized',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'response to hello');
    });
  });
}
