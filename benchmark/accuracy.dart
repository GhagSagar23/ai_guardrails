// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:ai_guardrails/ai_guardrails.dart';

Future<void> main() async {
  final file = File('test/fixtures/redteam/corpus.json');
  final json = jsonDecode(await file.readAsString()) as List;
  final corpus = BenchmarkCorpus.fromJsonList(json);

  // Use GuardAction.block everywhere so findings register as blocked
  // (passed=false) — measures detection accuracy, not default pipeline config.
  final guard = AiGuard(
    inputScanners: [
      PiiScanner(action: GuardAction.block),
      SecretScanner(action: GuardAction.block),
      PromptInjectionScanner(action: GuardAction.block),
      InvisibleTextScanner(action: GuardAction.block),
      UrlFormatValidator(action: GuardAction.block),
    ],
    outputScanners: [
      CodeExecutionScanner(),
      RepetitionScanner(),
      UrlFormatValidator(action: GuardAction.block),
    ],
  );

  final report = await GuardBenchmark(guard).run(corpus);

  print('# Per-category accuracy (${corpus.cases.length} prompts)\n');
  print('| Category | TP | FP | TN | FN | Precision | Recall | F1 |');
  print('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');

  final cats = List.of(report.categories)
    ..sort((a, b) => a.category.compareTo(b.category));

  for (final c in cats) {
    final m = c.metrics;
    print('| ${c.category} | ${m.truePositives} | ${m.falsePositives} '
        '| ${m.trueNegatives} | ${m.falseNegatives} '
        '| ${m.precision.toStringAsFixed(3)} '
        '| ${m.recall.toStringAsFixed(3)} '
        '| ${m.f1.toStringAsFixed(3)} |');
  }

  final o = report.overall;
  print('| **Overall** | **${o.truePositives}** | **${o.falsePositives}** '
      '| **${o.trueNegatives}** | **${o.falseNegatives}** '
      '| **${o.precision.toStringAsFixed(3)}** '
      '| **${o.recall.toStringAsFixed(3)}** '
      '| **${o.f1.toStringAsFixed(3)}** |');

  print('\n# Scanner finding counts\n');
  print('| Scanner | Cases flagged | Finding types |');
  print('| --- | ---: | --- |');
  for (final s in report.scanners) {
    final types = s.findingTypeCounts.entries
        .map((e) => '${e.key} (${e.value})')
        .join(', ');
    print('| ${s.name} | ${s.casesWithFindings} | $types |');
  }

  print('\n$o');
}
