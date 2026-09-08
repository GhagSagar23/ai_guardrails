import 'ai_guard.dart';
import 'scanner.dart';

/// A labeled test case for benchmarking scanner accuracy.
class BenchmarkCase {
  final String text;
  final ScanStage stage;
  final bool expectBlock;
  final Set<String> expectedTypes;
  final String? category;

  const BenchmarkCase({
    required this.text,
    this.stage = ScanStage.input,
    required this.expectBlock,
    this.expectedTypes = const {},
    this.category,
  });

  factory BenchmarkCase.fromJson(Map<String, dynamic> json) => BenchmarkCase(
        text: json['text'] as String,
        stage: (json['stage'] as String?) == 'output'
            ? ScanStage.output
            : ScanStage.input,
        expectBlock: json['expectBlock'] as bool,
        expectedTypes:
            (json['expectedTypes'] as List?)?.cast<String>().toSet() ??
                const {},
        category: json['category'] as String?,
      );
}

/// A collection of labeled test cases.
class BenchmarkCorpus {
  final List<BenchmarkCase> cases;

  const BenchmarkCorpus(this.cases);

  factory BenchmarkCorpus.fromJsonList(List<dynamic> data) => BenchmarkCorpus(
        data
            .map((e) => BenchmarkCase.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Accuracy metrics for a single scanner or the full pipeline.
class AccuracyMetrics {
  final int truePositives;
  final int falsePositives;
  final int trueNegatives;
  final int falseNegatives;

  const AccuracyMetrics({
    required this.truePositives,
    required this.falsePositives,
    required this.trueNegatives,
    required this.falseNegatives,
  });

  int get total =>
      truePositives + falsePositives + trueNegatives + falseNegatives;

  double get precision => (truePositives + falsePositives) == 0
      ? 1.0
      : truePositives / (truePositives + falsePositives);

  double get recall => (truePositives + falseNegatives) == 0
      ? 1.0
      : truePositives / (truePositives + falseNegatives);

  double get f1 {
    final p = precision;
    final r = recall;
    return (p + r) == 0 ? 0.0 : 2 * p * r / (p + r);
  }

  @override
  String toString() => 'AccuracyMetrics(P=${precision.toStringAsFixed(3)} '
      'R=${recall.toStringAsFixed(3)} F1=${f1.toStringAsFixed(3)} '
      'TP=$truePositives FP=$falsePositives TN=$trueNegatives FN=$falseNegatives)';
}

/// Per-scanner breakdown in a benchmark report.
class ScannerBenchmark {
  final String name;

  /// How many cases this scanner contributed findings to.
  final int casesWithFindings;

  /// Finding types this scanner produced, with counts.
  final Map<String, int> findingTypeCounts;

  const ScannerBenchmark({
    required this.name,
    required this.casesWithFindings,
    required this.findingTypeCounts,
  });
}

/// Per-category breakdown in a benchmark report.
class CategoryBenchmark {
  final String category;
  final AccuracyMetrics metrics;

  const CategoryBenchmark({required this.category, required this.metrics});
}

/// Full benchmark report.
class BenchmarkReport {
  final AccuracyMetrics overall;
  final List<ScannerBenchmark> scanners;
  final List<CategoryBenchmark> categories;

  const BenchmarkReport({
    required this.overall,
    required this.scanners,
    required this.categories,
  });
}

/// Runs a [BenchmarkCorpus] through an [AiGuard] and produces accuracy
/// metrics.
///
/// ```dart
/// final report = await GuardBenchmark(guard).run(corpus);
/// print(report.overall); // precision, recall, F1
/// ```
class GuardBenchmark {
  final AiGuard guard;

  const GuardBenchmark(this.guard);

  Future<BenchmarkReport> run(BenchmarkCorpus corpus) async {
    var tp = 0, fp = 0, tn = 0, fn = 0;
    final scannerFindings = <String, _ScannerAccum>{};
    final categoryAccum = <String, _CategoryAccum>{};

    for (final c in corpus.cases) {
      final results = c.stage == ScanStage.input
          ? await guard.scanInput(c.text)
          : await guard.scanOutput(c.text);

      final blocked = results.any((r) => !r.passed);
      final isTP = c.expectBlock && blocked;
      final isFP = !c.expectBlock && blocked;
      final isTN = !c.expectBlock && !blocked;
      final isFN = c.expectBlock && !blocked;

      if (isTP) tp++;
      if (isFP) fp++;
      if (isTN) tn++;
      if (isFN) fn++;

      // Per-scanner stats
      for (final r in results) {
        if (r.findings.isNotEmpty) {
          final a = scannerFindings.putIfAbsent(
              r.scanner, () => _ScannerAccum(r.scanner));
          a.casesWithFindings++;
          for (final f in r.findings) {
            a.typeCounts[f.type] = (a.typeCounts[f.type] ?? 0) + 1;
          }
        }
      }

      // Per-category stats
      if (c.category != null) {
        final cat =
            categoryAccum.putIfAbsent(c.category!, () => _CategoryAccum());
        if (isTP) cat.tp++;
        if (isFP) cat.fp++;
        if (isTN) cat.tn++;
        if (isFN) cat.fn++;
      }
    }

    return BenchmarkReport(
      overall: AccuracyMetrics(
        truePositives: tp,
        falsePositives: fp,
        trueNegatives: tn,
        falseNegatives: fn,
      ),
      scanners: scannerFindings.values
          .map((a) => ScannerBenchmark(
                name: a.name,
                casesWithFindings: a.casesWithFindings,
                findingTypeCounts: a.typeCounts,
              ))
          .toList(),
      categories: categoryAccum.entries
          .map((e) => CategoryBenchmark(
                category: e.key,
                metrics: AccuracyMetrics(
                  truePositives: e.value.tp,
                  falsePositives: e.value.fp,
                  trueNegatives: e.value.tn,
                  falseNegatives: e.value.fn,
                ),
              ))
          .toList(),
    );
  }
}

class _ScannerAccum {
  final String name;
  int casesWithFindings = 0;
  final typeCounts = <String, int>{};
  _ScannerAccum(this.name);
}

class _CategoryAccum {
  int tp = 0, fp = 0, tn = 0, fn = 0;
}
