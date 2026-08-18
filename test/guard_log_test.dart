import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('GuardLog', () {
    test('fromOutcome produces valid JSON with hashes, never raw text', () {
      final log = GuardLog.fromOutcome(
        blocked: false,
        inputText: 'secret user input',
        outputText: 'model response',
        inputResults: [
          ScanResult(
            scanner: 'pii',
            passed: true,
            text: 'redacted',
            score: 0.5,
            findings: [Finding(type: 'pii.email', match: 'a@b.com')],
          ),
        ],
        outputResults: [],
      );

      final json = log.toJson();
      expect(json['blocked'], isFalse);
      expect(json['input_hash'], isA<int>());
      expect(json['output_hash'], isA<int>());
      expect(json['total_findings'], 1);
      expect(json.containsKey('secret user input'), isFalse);

      final scanners = json['scanners'] as List;
      expect(scanners, hasLength(1));
      final entry = scanners[0] as Map;
      expect(entry['name'], 'pii');
      expect(entry['finding_count'], 1);
      expect(entry['finding_types'], ['pii.email']);
    });

    test('toJsonString produces parseable JSON', () {
      final log = GuardLog.fromOutcome(
        blocked: true,
        blockedStage: ScanStage.input,
        blockReason: 'test block',
        inputText: 'input',
        inputResults: [],
        outputResults: [],
      );
      final parsed = jsonDecode(log.toJsonString()) as Map<String, dynamic>;
      expect(parsed['blocked'], isTrue);
      expect(parsed['blocked_stage'], 'input');
      expect(parsed['block_reason'], 'test block');
    });

    test('blocked outcome omits output_hash as 0', () {
      final log = GuardLog.fromOutcome(
        blocked: true,
        blockedStage: ScanStage.input,
        inputText: 'x',
        inputResults: [],
        outputResults: [],
      );
      expect(log.outputHash, 0);
    });

    test('onScan callback fires on AiGuard.run', () async {
      GuardLog? captured;
      final guard = AiGuard(
        inputScanners: [PiiScanner(action: GuardAction.warn)],
        onScan: (log) => captured = log,
      );
      await guard.run(
        input: 'test a@b.com',
        llmCall: (s) async => 'ok',
      );
      expect(captured, isNotNull);
      expect(captured!.totalFindings, greaterThan(0));
      expect(captured!.blocked, isFalse);
    });

    test('onScan fires on blocked input', () async {
      GuardLog? captured;
      final guard = AiGuard(
        inputScanners: [SecretScanner()],
        onScan: (log) => captured = log,
      );
      await guard.run(
        input: 'key AKIAIOSFODNN7EXAMPLE',
        llmCall: (s) async => 'ok',
      );
      expect(captured, isNotNull);
      expect(captured!.blocked, isTrue);
    });
  });
}
