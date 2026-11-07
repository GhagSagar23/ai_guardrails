# Benchmarks

Run from the repository root.

```sh
dart run benchmark/latency_benchmark.dart    # -> benchmark/results/latency.json
dart run benchmark/accuracy_benchmark.dart   # -> benchmark/results/accuracy.json
```

(`benchmark.dart` and `accuracy.dart` in this folder are the older throughput
and red-team-corpus benchmarks; they are independent of the two above.)

## Latency

Each sync scanner is built with defaults (a minimal config where a
constructor argument is required) and run 1000 times, after 100 warm-up runs,
on one ~190-word English prose text. Every run is timed individually with a
`Stopwatch`.

| Column | Meaning |
| --- | --- |
| mean us | Average time per scan, microseconds |
| median us | 50th percentile |
| p99 us | 99th percentile (tail latency; 1 slow run in 100) |
| ops/sec | `1e6 / mean us`, scans per second on one isolate |

The `AiGuard pipeline` row chains pii, secret, prompt_injection,
banned_topic and repetition via `scanInput`.

Skipped (need external LLM/embedding callbacks): SemanticInjectionScanner,
EmbeddingGroundingScanner, TopicSafetyScanner, FactCheckScanner,
HallucinationScanner, BiasScanner, TopicAllowlistScanner.

Caveats: the text is clean prose, so scanners that exit early on a match are
timed on their no-finding path. Values of 0 to 1 us are at `Stopwatch`
resolution and mean "negligible", not an exact figure.

## Accuracy

50 hand-written labelled cases (5 harmful + 5 clean for each of pii, secret,
prompt_injection, toxicity, url) go through one `AiGuard` using
`GuardBenchmark`. A case counts as blocked if any scanner fails it, so
cross-category false positives are included.

- Precision = TP / (TP + FP): of the cases flagged, how many were truly harmful.
- Recall = TP / (TP + FN): of the harmful cases, how many were flagged.
- F1 = harmonic mean of precision and recall.

Caveats:

- The core package has no toxicity scanner. The toxicity category uses a
  `BannedPatternScanner` keyword list as a stand-in, so it measures a keyword
  baseline, not a real toxicity classifier.
- The corpus is small and easy. Perfect scores show the scanners work on
  textbook cases; they are not a claim about real-world traffic. Use
  `benchmark/accuracy.dart` (red-team corpus) for harder cases.

## Environment

`latency.json` records the Dart version, OS and CPU count of the run. Results
vary with CPU, thermal state, background load and Dart version (JIT via
`dart run`; AOT via `dart compile exe` is usually faster). Compare numbers
only across runs on the same machine. The committed results were produced on
a single developer laptop and are a reference point, not a guarantee.
