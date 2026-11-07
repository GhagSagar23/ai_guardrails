// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:ai_guardrails/ai_guardrails.dart';

/// Per-scanner latency benchmark: [kRuns] timed runs of each sync scanner
/// (default config) on a ~200-word prose text, plus a 5-scanner AiGuard
/// pipeline. Async/LLM-dependent scanners are skipped (need callbacks):
/// SemanticInjection, EmbeddingGrounding, TopicSafety, FactCheck,
/// Hallucination, Bias, TopicAllowlist.
const int kRuns = 1000;
const int kWarmup = 100;

const String kText =
    'Last spring our small team decided to rebuild the onboarding experience '
    'for a mobile application that helps neighbourhood libraries share their '
    'catalogues. We started by interviewing a dozen volunteers, who explained '
    'that the old screens were confusing and that new members often gave up '
    'before borrowing their first book. After several workshops we sketched a '
    'simpler flow with three short steps, friendly illustrations and plain '
    'language. The developers then spent a few weeks building the new screens, '
    'while the designers refined colours, spacing and typography so that '
    'everything felt calm and welcoming. Testing with real readers revealed '
    'a handful of rough edges, such as a button that was hard to reach with '
    'one hand and a message that appeared too quickly to read. We fixed those '
    'problems, wrote clear documentation for future contributors, and '
    'released the update on a quiet Tuesday morning. Within a month the '
    'number of completed sign-ups had grown noticeably, volunteers reported '
    'fewer questions at the front desk, and several libraries asked whether '
    'we could adapt the design for their own community events and lending '
    'programmes. We plan to keep listening, measuring and improving.';

class Row {
  final String name;
  final double meanUs, medianUs, p99Us, opsPerSec;

  Row(this.name, List<int> us)
      : meanUs = us.reduce((a, b) => a + b) / us.length,
        medianUs = _pct(us, 0.5),
        p99Us = _pct(us, 0.99),
        opsPerSec = 1e6 / (us.reduce((a, b) => a + b) / us.length);

  static double _pct(List<int> us, double p) {
    final s = [...us]..sort();
    return s[((s.length - 1) * p).round()].toDouble();
  }

  Map<String, Object> toJson() => {
        'scanner': name,
        'mean_us': meanUs,
        'median_us': medianUs,
        'p99_us': p99Us,
        'ops_per_sec': opsPerSec,
      };
}

/// Times [fn] [kRuns] times; each run measured individually in microseconds.
Future<Row> measure(String name, Future<void> Function() fn) async {
  for (var i = 0; i < kWarmup; i++) {
    await fn();
  }
  final us = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < kRuns; i++) {
    sw
      ..reset()
      ..start();
    await fn();
    sw.stop();
    us.add(sw.elapsedMicroseconds);
  }
  return Row(name, us);
}

Future<void> main() async {
  final words = kText.split(RegExp(r'\s+')).length;
  final scanners = <Scanner>[
    PiiScanner(),
    SecretScanner(),
    PromptInjectionScanner(),
    BannedTopicScanner(['weapons', 'malware']),
    BannedPatternScanner([RegExp('forbidden')]),
    TokenLimitScanner(),
    InvisibleTextScanner(),
    RepetitionScanner(),
    UrlScanner(),
    LanguageScanner(),
    CodeExecutionScanner(),
    GroundingScanner(context: kText),
    SchemaValidator({'type': 'object'}),
    ToolCallScanner(),
    PaddingAttackScanner(),
    ToolOutputScanner(),
    JsonValidator(),
    HtmlValidator(),
    SqlValidator(),
    UrlFormatValidator(),
    RangeValidator(),
    ChoicesValidator(['yes', 'no']),
    CompetitorMentionScanner(['acme']),
    PolitenessScanner(targetRegister: ToneRegister.neutral),
    ReadingLevelScanner(),
  ];

  var sink = 0; // fold results so work can't be optimised away
  final rows = <Row>[];
  for (final s in scanners) {
    final stage =
        s.stages.contains(ScanStage.input) ? ScanStage.input : ScanStage.output;
    rows.add(await measure(s.name, () async {
      sink += s.scan(kText, stage: stage).findings.length;
    }));
  }

  final guard = AiGuard(inputScanners: [
    PiiScanner(),
    SecretScanner(),
    PromptInjectionScanner(),
    BannedTopicScanner(['weapons', 'malware']),
    RepetitionScanner(),
  ]);
  rows.add(await measure('AiGuard pipeline (5 scanners)', () async {
    sink += (await guard.scanInput(kText)).length;
  }));

  final sb = StringBuffer()
    ..writeln('Latency: $kRuns runs/scanner, $words-word text, sink=$sink')
    ..writeln('${'Scanner'.padRight(34)}${'mean us'.padLeft(10)}'
        '${'median us'.padLeft(11)}${'p99 us'.padLeft(10)}'
        '${'ops/sec'.padLeft(12)}');
  for (final r in rows) {
    sb.writeln('${r.name.padRight(34)}'
        '${r.meanUs.toStringAsFixed(1).padLeft(10)}'
        '${r.medianUs.toStringAsFixed(1).padLeft(11)}'
        '${r.p99Us.toStringAsFixed(1).padLeft(10)}'
        '${r.opsPerSec.toStringAsFixed(0).padLeft(12)}');
  }
  print(sb.toString().trimRight());

  Directory('benchmark/results').createSync(recursive: true);
  File('benchmark/results/latency.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'runs': kRuns,
      'words': words,
      'dart': Platform.version.split(' ').first,
      'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'cpus': Platform.numberOfProcessors,
      'results': [for (final r in rows) r.toJson()],
    }),
  );
}
