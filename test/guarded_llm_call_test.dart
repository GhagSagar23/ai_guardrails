import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

class _ReaskScanner implements Scanner {
  int callCount = 0;
  final int passAfter;
  _ReaskScanner({this.passAfter = 2});

  @override
  String get name => 'reask_test';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    callCount++;
    if (callCount > passAfter) return ScanResult.pass(name, text);
    return ScanResult.block(name, text,
        findings: [const Finding(type: 'reask_test.bad')],
        reason: 'output not acceptable');
  }
}

class _AlwaysBlockScanner implements Scanner {
  @override
  String get name => 'always_block';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.block(name, text,
          findings: [const Finding(type: 'always_block.issue')],
          reason: 'always blocks');
}

void main() {
  group('GuardedLlmCall', () {
    test('passes through clean responses immediately', () async {
      final guard = AiGuard();
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 3);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'clean response';
        },
      );

      expect(outcome.blocked, isFalse);
      expect(outcome.output, 'clean response');
      expect(llmCalls, 1);
    });

    test('retries on reask until scanner passes', () async {
      final scanner = _ReaskScanner(passAfter: 2);
      final guard = AiGuard(
        outputScanners: [scanner],
        onFailActions: {'reask_test': OnFailAction.reask},
      );
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 5);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'response attempt $llmCalls';
        },
      );

      expect(outcome.blocked, isFalse);
      expect(llmCalls, 3);
    });

    test('stops after maxReasks exceeded', () async {
      final scanner = _AlwaysBlockScanner();
      final guard = AiGuard(
        outputScanners: [scanner],
        onFailActions: {'always_block': OnFailAction.reask},
      );
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 2);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'bad response';
        },
      );

      expect(outcome.blocked, isTrue);
      expect(outcome.failAction, OnFailAction.reask);
      expect(llmCalls, 3);
    });

    test('non-reask block returns immediately', () async {
      final scanner = _AlwaysBlockScanner();
      final guard = AiGuard(outputScanners: [scanner]);
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 5);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'bad';
        },
      );

      expect(outcome.blocked, isTrue);
      expect(llmCalls, 1);
    });

    test('custom retryPromptBuilder is used', () async {
      final scanner = _ReaskScanner(passAfter: 1);
      final guard = AiGuard(
        outputScanners: [scanner],
        onFailActions: {'reask_test': OnFailAction.reask},
      );

      String? retryInput;
      final guarded = GuardedLlmCall(
        guard: guard,
        maxReasks: 3,
        retryPromptBuilder: (original, outcome) {
          return 'CUSTOM_RETRY: $original';
        },
      );

      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          retryInput = s;
          return 'response';
        },
      );

      expect(outcome.blocked, isFalse);
      expect(retryInput, contains('CUSTOM_RETRY'));
    });

    test('defaultRetryPrompt includes rejection reason', () {
      final outcome = GuardOutcome(
        blocked: true,
        blockReason: 'output not acceptable',
        failAction: OnFailAction.reask,
        inputResults: [],
        outputResults: [
          ScanResult.block('test', 'bad',
              findings: [const Finding(type: 'test.issue')],
              reason: 'output not acceptable'),
        ],
      );

      final prompt =
          GuardedLlmCall.defaultRetryPrompt('original input', outcome);
      expect(prompt, contains('original input'));
      expect(prompt, contains('output not acceptable'));
    });

    test('maxReasks=0 means no retries', () async {
      final scanner = _AlwaysBlockScanner();
      final guard = AiGuard(
        outputScanners: [scanner],
        onFailActions: {'always_block': OnFailAction.reask},
      );
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 0);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'bad';
        },
      );

      expect(outcome.blocked, isTrue);
      expect(llmCalls, 1);
    });

    test('input block does not trigger reask', () async {
      final guard = AiGuard(
        inputScanners: [_AlwaysBlockScanner()],
        onFailActions: {'always_block': OnFailAction.reask},
      );
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 3);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'response';
        },
      );

      expect(outcome.blocked, isTrue);
      expect(llmCalls, 0);
    });

    test('refrain returns immediately without retry', () async {
      final guard = AiGuard(
        outputScanners: [_AlwaysBlockScanner()],
        onFailActions: {'always_block': OnFailAction.refrain},
      );
      final guarded = GuardedLlmCall(guard: guard, maxReasks: 5);

      var llmCalls = 0;
      final outcome = await guarded.call(
        input: 'hello',
        llmCall: (s) async {
          llmCalls++;
          return 'bad';
        },
      );

      expect(outcome.blocked, isFalse);
      expect(outcome.failAction, OnFailAction.refrain);
      expect(llmCalls, 1);
    });
  });
}
