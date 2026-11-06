import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_langchain/ai_guardrails_langchain.dart';
import 'package:langchain_core/chains.dart';
import 'package:test/test.dart';

class _EchoChain extends BaseChain {
  final String prefix;
  _EchoChain({this.prefix = 'Echo: '});

  @override
  String get chainType => 'echo';
  @override
  Set<String> get inputKeys => {'input'};
  @override
  Set<String> get outputKeys => {'output'};

  @override
  Future<ChainValues> callInternal(ChainValues inputs) async {
    return {'output': '$prefix${inputs['input']}'};
  }
}

class _FixedOutputChain extends BaseChain {
  final String fixedOutput;
  _FixedOutputChain(this.fixedOutput);

  @override
  String get chainType => 'fixed';
  @override
  Set<String> get inputKeys => {'input'};
  @override
  Set<String> get outputKeys => {'output'};

  @override
  Future<ChainValues> callInternal(ChainValues inputs) async {
    return {'output': fixedOutput};
  }
}

void main() {
  group('GuardrailsChain', () {
    test('passes clean text through', () async {
      final guard = AiGuard();
      final chain = GuardrailsChain(
        guard: guard,
        innerChain: _EchoChain(),
      );

      final result = await chain.call(
        {'input': 'Hello world'},
        returnOnlyOutputs: true,
      );

      expect(result['output'], 'Echo: Hello world');
      expect(result['guardrails_blocked'], false);
      expect(result['guardrails_input_results'], isA<List<ScanResult>>());
      expect(result['guardrails_output_results'], isA<List<ScanResult>>());
    });

    test('blocks on input with secret', () async {
      final guard = AiGuard(inputScanners: [
        SecretScanner(),
      ]);
      final chain = GuardrailsChain(
        guard: guard,
        innerChain: _EchoChain(),
      );

      expect(
        () => chain.call({'input': 'key: AKIAIOSFODNN7EXAMPLE'}),
        throwsA(isA<GuardrailsBlockedException>().having(
          (e) => e.stage,
          'stage',
          'input',
        )),
      );
    });

    test('blocks on output with secret', () async {
      final guard = AiGuard(outputScanners: [
        SecretScanner(),
      ]);
      final chain = GuardrailsChain(
        guard: guard,
        innerChain: _FixedOutputChain('Here is the key: AKIAIOSFODNN7EXAMPLE'),
      );

      expect(
        () => chain.call({'input': 'show me'}),
        throwsA(isA<GuardrailsBlockedException>().having(
          (e) => e.stage,
          'stage',
          'output',
        )),
      );
    });

    test('throwOnBlock: false returns blocked result', () async {
      final guard = AiGuard(inputScanners: [
        SecretScanner(),
      ]);
      final chain = GuardrailsChain(
        guard: guard,
        innerChain: _EchoChain(),
        throwOnBlock: false,
      );

      final result = await chain.call(
        {'input': 'key: AKIAIOSFODNN7EXAMPLE'},
        returnOnlyOutputs: true,
      );

      expect(result['guardrails_blocked'], true);
    });

    test('PII redaction round-trips through inner chain', () async {
      final guard = AiGuard(
        inputScanners: [PiiScanner()],
      );
      final chain = GuardrailsChain(
        guard: guard,
        innerChain: _EchoChain(prefix: 'Got: '),
      );

      final result = await chain.call(
        {'input': 'Call me at 555-123-4567'},
        returnOnlyOutputs: true,
      );

      final output = result['output'] as String;
      expect(output, contains('555-123-4567'));
      expect(result['guardrails_blocked'], false);
      final redactionMap =
          result['guardrails_redaction_map'] as Map<String, String>;
      expect(redactionMap, isNotEmpty);
    });

    test('output keys include guardrails metadata', () {
      final chain = GuardrailsChain(
        guard: AiGuard(),
        innerChain: _EchoChain(),
      );

      expect(
          chain.outputKeys,
          containsAll([
            'output',
            'guardrails_blocked',
            'guardrails_input_results',
            'guardrails_output_results',
            'guardrails_redaction_map',
          ]));
    });

    test('chainType is guardrails', () {
      final chain = GuardrailsChain(
        guard: AiGuard(),
        innerChain: _EchoChain(),
      );
      expect(chain.chainType, 'guardrails');
    });

    test('inputKeys delegates to inner chain', () {
      final chain = GuardrailsChain(
        guard: AiGuard(),
        innerChain: _EchoChain(),
      );
      expect(chain.inputKeys, {'input'});
    });

    test('GuardrailsBlockedException toString is readable', () {
      const e = GuardrailsBlockedException(
        stage: 'input',
        reason: 'Secret detected',
        results: [],
      );
      expect(e.toString(), contains('input'));
      expect(e.toString(), contains('Secret detected'));
    });

    test('output blocked returns empty output values', () async {
      final guard = AiGuard(outputScanners: [
        SecretScanner(),
      ]);
      final chain = GuardrailsChain(
        guard: guard,
        innerChain: _FixedOutputChain('secret AKIAIOSFODNN7EXAMPLE'),
        throwOnBlock: false,
      );

      final result = await chain.call(
        {'input': 'show me'},
        returnOnlyOutputs: true,
      );

      expect(result['guardrails_blocked'], true);
      expect(result['guardrails_output_results'], isNotEmpty);
    });
  });
}
