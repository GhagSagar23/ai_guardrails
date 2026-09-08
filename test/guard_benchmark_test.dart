import 'dart:convert';
import 'dart:io';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('BenchmarkCase', () {
    test('fromJson parses correctly', () {
      final c = BenchmarkCase.fromJson({
        'text': 'hello',
        'stage': 'input',
        'expectBlock': false,
        'expectedTypes': ['pii.email'],
        'category': 'benign',
      });
      expect(c.text, 'hello');
      expect(c.stage, ScanStage.input);
      expect(c.expectBlock, isFalse);
      expect(c.expectedTypes, contains('pii.email'));
      expect(c.category, 'benign');
    });

    test('defaults to input stage', () {
      final c = BenchmarkCase.fromJson({
        'text': 'hi',
        'expectBlock': false,
      });
      expect(c.stage, ScanStage.input);
    });
  });

  group('BenchmarkCorpus', () {
    test('fromJsonList parses list', () {
      final corpus = BenchmarkCorpus.fromJsonList([
        {'text': 'a', 'expectBlock': true},
        {'text': 'b', 'expectBlock': false},
      ]);
      expect(corpus.cases, hasLength(2));
    });
  });

  group('AccuracyMetrics', () {
    test('perfect precision and recall', () {
      const m = AccuracyMetrics(
        truePositives: 10,
        falsePositives: 0,
        trueNegatives: 10,
        falseNegatives: 0,
      );
      expect(m.precision, 1.0);
      expect(m.recall, 1.0);
      expect(m.f1, 1.0);
      expect(m.total, 20);
    });

    test('zero division handled', () {
      const m = AccuracyMetrics(
        truePositives: 0,
        falsePositives: 0,
        trueNegatives: 5,
        falseNegatives: 0,
      );
      expect(m.precision, 1.0);
      expect(m.recall, 1.0);
    });

    test('f1 calculation', () {
      const m = AccuracyMetrics(
        truePositives: 8,
        falsePositives: 2,
        trueNegatives: 7,
        falseNegatives: 3,
      );
      expect(m.precision, closeTo(0.8, 0.01));
      expect(m.recall, closeTo(0.727, 0.01));
      expect(m.f1, greaterThan(0));
    });
  });

  group('GuardBenchmark', () {
    test('all benign passes gives perfect TN', () async {
      final guard = AiGuard(inputScanners: [SecretScanner()]);
      final corpus = BenchmarkCorpus([
        const BenchmarkCase(text: 'Hello world', expectBlock: false),
        const BenchmarkCase(text: 'Nice weather', expectBlock: false),
      ]);
      final report = await GuardBenchmark(guard).run(corpus);
      expect(report.overall.trueNegatives, 2);
      expect(report.overall.falsePositives, 0);
    });

    test('detects TP and FN', () async {
      final guard = AiGuard(inputScanners: [SecretScanner()]);
      final corpus = BenchmarkCorpus([
        const BenchmarkCase(
          text: 'Key: AKIAIOSFODNN7EXAMPLE',
          expectBlock: true,
        ),
        const BenchmarkCase(
          text: 'Normal text that should block but wont',
          expectBlock: true,
        ),
      ]);
      final report = await GuardBenchmark(guard).run(corpus);
      expect(report.overall.truePositives, 1);
      expect(report.overall.falseNegatives, 1);
    });

    test('per-category breakdown', () async {
      final guard = AiGuard(inputScanners: [SecretScanner()]);
      final corpus = BenchmarkCorpus([
        const BenchmarkCase(
          text: 'AKIAIOSFODNN7EXAMPLE',
          expectBlock: true,
          category: 'secret',
        ),
        const BenchmarkCase(
          text: 'Hello',
          expectBlock: false,
          category: 'benign',
        ),
      ]);
      final report = await GuardBenchmark(guard).run(corpus);
      expect(report.categories, hasLength(2));
    });

    test('per-scanner breakdown', () async {
      final guard = AiGuard(inputScanners: [SecretScanner(), PiiScanner()]);
      final corpus = BenchmarkCorpus([
        const BenchmarkCase(
          text: 'Email test@example.com key AKIAIOSFODNN7EXAMPLE',
          expectBlock: true,
        ),
      ]);
      final report = await GuardBenchmark(guard).run(corpus);
      expect(report.scanners, isNotEmpty);
    });

    test('output stage benchmark', () async {
      final guard = AiGuard(outputScanners: [
        CodeExecutionScanner(),
      ]);
      final corpus = BenchmarkCorpus([
        const BenchmarkCase(
          text: 'rm -rf / --no-preserve-root',
          stage: ScanStage.output,
          expectBlock: true,
        ),
        const BenchmarkCase(
          text: 'print("hello")',
          stage: ScanStage.output,
          expectBlock: false,
        ),
      ]);
      final report = await GuardBenchmark(guard).run(corpus);
      expect(report.overall.truePositives, 1);
      expect(report.overall.trueNegatives, 1);
    });
  });

  group('Red-team corpus', () {
    late BenchmarkCorpus corpus;

    setUpAll(() {
      final file = File('test/fixtures/redteam/corpus.json');
      final data = jsonDecode(file.readAsStringSync()) as List;
      corpus = BenchmarkCorpus.fromJsonList(data);
    });

    test('corpus loads and is non-empty', () {
      expect(corpus.cases.length, greaterThanOrEqualTo(50));
    });

    test('all cases have required fields', () {
      for (final c in corpus.cases) {
        expect(c.text, isNotEmpty, reason: 'empty text in corpus');
        expect(c.category, isNotNull, reason: 'missing category');
      }
    });

    test('has both positive and negative cases', () {
      expect(corpus.cases.any((c) => c.expectBlock), isTrue);
      expect(corpus.cases.any((c) => !c.expectBlock), isTrue);
    });

    test('has diverse categories', () {
      final categories = corpus.cases.map((c) => c.category).toSet();
      expect(categories, containsAll(['prompt_injection', 'pii', 'benign']));
    });

    test('benchmark runs against corpus', () async {
      final guard = AiGuard(
        inputScanners: [
          PiiScanner(action: GuardAction.warn),
          SecretScanner(action: GuardAction.warn),
          PromptInjectionScanner(threshold: 0.5, action: GuardAction.warn),
          InvisibleTextScanner(action: GuardAction.warn),
          UrlScanner(action: GuardAction.warn),
        ],
        outputScanners: [
          CodeExecutionScanner(action: GuardAction.warn),
          RepetitionScanner(action: GuardAction.warn),
        ],
      );

      final report = await GuardBenchmark(guard).run(corpus);
      expect(report.overall.total, corpus.cases.length);
      expect(report.categories, isNotEmpty);
    });
  });
}
