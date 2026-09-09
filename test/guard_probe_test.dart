import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('ProbeResult', () {
    test('computes catch rate', () {
      const r = ProbeResult(scanner: 'pii', totalProbes: 10, bypassed: 3);
      expect(r.caught, 7);
      expect(r.catchRate, closeTo(0.7, 0.001));
      expect(r.bypassRate, closeTo(0.3, 0.001));
    });

    test('zero probes gives zero rates', () {
      const r = ProbeResult(scanner: 'x', totalProbes: 0, bypassed: 0);
      expect(r.catchRate, 1.0);
      expect(r.bypassRate, 0.0);
    });
  });

  group('ProbeReport', () {
    test('aggregates across scanners', () {
      const report = ProbeReport(
        scanners: [
          ProbeResult(scanner: 'a', totalProbes: 5, bypassed: 1),
          ProbeResult(scanner: 'b', totalProbes: 5, bypassed: 2),
        ],
        elapsed: Duration.zero,
      );
      expect(report.totalProbes, 10);
      expect(report.totalBypassed, 3);
      expect(report.totalCaught, 7);
      expect(report.resilienceScore, closeTo(0.7, 0.001));
    });

    test('empty report gives perfect resilience', () {
      const report = ProbeReport(scanners: [], elapsed: Duration.zero);
      expect(report.resilienceScore, 1.0);
    });
  });

  group('GuardProbe.run', () {
    test('probes PII scanner', () async {
      final guard = AiGuard(inputScanners: [PiiScanner()]);
      final report = await GuardProbe(guard).run();

      expect(report.scanners, isNotEmpty);
      final pii = report.scanners.firstWhere((r) => r.scanner == 'pii');
      expect(pii.totalProbes, greaterThan(0));
      // Some evasion probes should bypass the regex scanner
      expect(pii.bypassed, greaterThan(0),
          reason: 'evasion probes should bypass regex PII');
    });

    test('probes prompt injection scanner', () async {
      final guard =
          AiGuard(inputScanners: [PromptInjectionScanner(threshold: 0.5)]);
      final report = await GuardProbe(guard).run();

      expect(report.scanners, isNotEmpty);
      final inj =
          report.scanners.firstWhere((r) => r.scanner == 'prompt_injection');
      expect(inj.totalProbes, greaterThan(0));
    });

    test('probes output-stage scanners', () async {
      final guard = AiGuard(outputScanners: [CodeExecutionScanner()]);
      final report = await GuardProbe(guard).run();

      expect(report.scanners, isNotEmpty);
      final codeExec =
          report.scanners.firstWhere((r) => r.scanner == 'code_exec');
      expect(codeExec.totalProbes, greaterThan(0));
      expect(codeExec.caught, greaterThan(0),
          reason: 'code_exec should catch some direct probes');
    });

    test('skips scanners without probe sets', () async {
      final guard = AiGuard(inputScanners: [
        BannedTopicScanner(['politics']),
      ]);
      final report = await GuardProbe(guard).run();

      expect(report.scanners, isEmpty, reason: 'no probe set for banned_topic');
    });

    test('reports elapsed time', () async {
      final guard = AiGuard(inputScanners: [PiiScanner()]);
      final report = await GuardProbe(guard).run();
      expect(report.elapsed, isNotNull);
    });

    test('resilience score is between 0 and 1', () async {
      final guard = AiGuard(inputScanners: [
        PiiScanner(),
        SecretScanner(),
        PromptInjectionScanner(threshold: 0.5),
      ]);
      final report = await GuardProbe(guard).run();
      expect(report.resilienceScore, greaterThanOrEqualTo(0.0));
      expect(report.resilienceScore, lessThanOrEqualTo(1.0));
    });

    test('multiple scanners produce multiple results', () async {
      final guard = AiGuard(inputScanners: [
        PiiScanner(),
        PromptInjectionScanner(threshold: 0.5),
        InvisibleTextScanner(),
      ]);
      final report = await GuardProbe(guard).run();
      expect(report.scanners.length, 3);
    });

    test('bypassed inputs are recorded', () async {
      final guard = AiGuard(inputScanners: [PiiScanner()]);
      final report = await GuardProbe(guard).run();
      final pii = report.scanners.firstWhere((r) => r.scanner == 'pii');
      expect(pii.bypassedInputs.length, pii.bypassed);
    });

    test('invisible text probes are mostly caught', () async {
      final guard = AiGuard(inputScanners: [InvisibleTextScanner()]);
      final report = await GuardProbe(guard).run();
      final inv =
          report.scanners.firstWhere((r) => r.scanner == 'invisible_text');
      expect(inv.catchRate, greaterThan(0.5),
          reason: 'InvisibleTextScanner should catch most probes');
    });

    test('URL probes are mostly caught', () async {
      final guard = AiGuard(inputScanners: [UrlScanner()]);
      final report = await GuardProbe(guard).run();
      final url = report.scanners.firstWhere((r) => r.scanner == 'url');
      expect(url.catchRate, greaterThan(0.5),
          reason: 'UrlScanner should catch most probes');
    });
  });
}
