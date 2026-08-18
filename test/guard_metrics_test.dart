import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('GuardMetrics', () {
    test('onMetrics callback fires with timing data', () async {
      GuardMetrics? captured;
      final guard = AiGuard(
        inputScanners: [PiiScanner(action: GuardAction.warn)],
        onMetrics: (m) => captured = m,
      );
      await guard.run(
        input: 'contact a@b.com please',
        llmCall: (s) async => 'done',
      );
      expect(captured, isNotNull);
      expect(captured!.totalDuration.inMicroseconds, greaterThan(0));
      expect(captured!.inputDuration.inMicroseconds, greaterThan(0));
      expect(captured!.blocked, isFalse);
      expect(captured!.totalFindings, greaterThan(0));
      expect(captured!.scanners, hasLength(1));
      expect(captured!.scanners.first.name, 'pii');
    });

    test('blocked input reports zero output duration', () async {
      GuardMetrics? captured;
      final guard = AiGuard(
        inputScanners: [SecretScanner()],
        onMetrics: (m) => captured = m,
      );
      await guard.run(
        input: 'key AKIAIOSFODNN7EXAMPLE',
        llmCall: (s) async => 'ok',
      );
      expect(captured, isNotNull);
      expect(captured!.blocked, isTrue);
      expect(captured!.outputDuration, Duration.zero);
    });

    test('both onScan and onMetrics fire together', () async {
      var scanCount = 0;
      var metricsCount = 0;
      final guard = AiGuard(
        onScan: (_) => scanCount++,
        onMetrics: (_) => metricsCount++,
      );
      await guard.run(input: 'hi', llmCall: (s) async => 'hello');
      expect(scanCount, 1);
      expect(metricsCount, 1);
    });
  });
}
