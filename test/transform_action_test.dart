import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

/// A scanner that strips dangerous URLs from output, recording what it removed.
class _UrlStripScanner implements Scanner {
  @override
  String get name => 'url_strip';
  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final pattern = RegExp(r'https?://\S+');
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return ScanResult.pass(name, text);

    var transformed = text;
    final transforms = <String, String>{};
    for (final m in matches) {
      final url = m.group(0)!;
      transforms[url] = '[URL_REMOVED]';
      transformed = transformed.replaceFirst(url, '[URL_REMOVED]');
    }

    return ScanResult.transform(
      name,
      transformed,
      findings: [
        for (final m in matches)
          Finding(
            type: 'url_strip.removed',
            start: m.start,
            end: m.end,
            match: m.group(0),
          ),
      ],
      transformations: transforms,
      reason: 'stripped ${matches.length} URL(s)',
    );
  }
}

void main() {
  group('GuardAction.transform', () {
    test('enum value exists', () {
      expect(GuardAction.values, contains(GuardAction.transform));
    });

    test('parseGuardAction handles transform', () {
      expect(parseGuardAction('transform'), GuardAction.transform);
    });
  });

  group('ScanResult.transform', () {
    test('passes and records transformations', () {
      const r = ScanResult.transform(
        'test',
        'clean text',
        findings: [Finding(type: 'test.t')],
        transformations: {'dirty': 'clean'},
      );
      expect(r.passed, isTrue);
      expect(r.transformations, {'dirty': 'clean'});
      expect(r.redactionMap, isEmpty);
    });
  });

  group('Transform in pipeline', () {
    test('scanner strips URLs and records transformations', () {
      final scanner = _UrlStripScanner();
      final result = scanner.scan(
        'Visit https://evil.com/malware for details',
        stage: ScanStage.output,
      );
      expect(result.passed, isTrue);
      expect(result.text, contains('[URL_REMOVED]'));
      expect(result.text, isNot(contains('https://evil.com')));
      expect(result.transformations, isNotEmpty);
      expect(result.findings, hasLength(1));
    });

    test('clean text passes through', () {
      final scanner = _UrlStripScanner();
      final result = scanner.scan('No URLs here', stage: ScanStage.output);
      expect(result.passed, isTrue);
      expect(result.transformations, isEmpty);
    });

    test('AiGuard chains transforms and exposes them', () async {
      final guard = AiGuard(
        outputScanners: [_UrlStripScanner()],
      );
      final outcome = await guard.run(
        input: 'question',
        llmCall: (_) async =>
            'See https://evil.com and https://bad.org for more',
      );
      expect(outcome.blocked, isFalse);
      expect(outcome.output, contains('[URL_REMOVED]'));
      expect(outcome.transformations, hasLength(2));
    });

    test('transforms are not reversed like redactions', () async {
      final guard = AiGuard(
        inputScanners: [PiiScanner(action: GuardAction.redact)],
        outputScanners: [_UrlStripScanner()],
      );
      final outcome = await guard.run(
        input: 'Email: test@example.com',
        llmCall: (_) async => 'Visit https://example.com',
      );
      expect(outcome.blocked, isFalse);
      // PII redaction is reversed in output
      expect(outcome.piiMap, isNotEmpty);
      // URL transform stays permanent
      expect(outcome.output, contains('[URL_REMOVED]'));
      expect(outcome.transformations, isNotEmpty);
    });

    test('StageRun carries transformations', () async {
      final guard = AiGuard(outputScanners: [_UrlStripScanner()]);
      final run = await guard.runOutputStage('Check https://evil.com');
      expect(run.transformations, isNotEmpty);
    });

    test('multiple transform scanners merge', () async {
      final guard = AiGuard(
        outputScanners: [_UrlStripScanner(), _UrlStripScanner()],
      );
      final results = await guard.scanOutput(
        'See https://a.com and more text',
      );
      final allTransforms = {
        for (final r in results) ...r.transformations,
      };
      expect(allTransforms, isNotEmpty);
    });

    test('blocked outcome still carries transformations', () async {
      final guard = AiGuard(
        outputScanners: [
          _UrlStripScanner(),
          CodeExecutionScanner(),
        ],
      );
      final outcome = await guard.run(
        input: 'q',
        llmCall: (_) async => 'Run rm -rf / and see https://evil.com for more',
      );
      expect(outcome.blocked, isTrue);
      expect(outcome.transformations, isNotEmpty);
    });
  });
}
