# Benchmark

Micro-benchmarks for every scanner and the full `AiGuard` input pipeline.
Source: [`benchmark/benchmark.dart`](benchmark/benchmark.dart).

## Methodology

### Corpus construction

`buildCorpus()` builds a fixed, deterministic corpus of **200 strings** from a
seeded PRNG (`Random(1997)`), so every run scans identical bytes:

- **180 free-text strings**, each padded to a random length in **500–2000
  chars**. Six kinds cycle by index so the corpus is a realistic mix of clean
  and violating text:
  1. clean filler prose,
  2. a single PII/secret/injection violator + filler,
  3. two violators plus an invisible-character smuggling fragment,
  4. clean preamble followed by a violator,
  5. clean long text (long enough to trip the token limit at a low budget),
  6. invisible fragment followed by a violator.
- **20 JSON payloads** for `SchemaValidator`, with padded properties, cycling
  through: valid / wrong-type / missing-required-key / parse-failure. This
  exercises the real `jsonDecode` + validate path, not just the happy case.

Because the seed is fixed, the corpus (and therefore the byte totals below) is
reproducible across machines.

### Warm-up

Each scanner runs **5,000 warm-up iterations** before timing starts. The
warm-up results are discarded from the measured time but folded into a running
checksum (see below), so the JIT has tiered up and regex objects are compiled
before the stopwatch runs.

### Iteration count

Each scanner is then timed over **100,000 iterations**, cycling through the
corpus with `corpus[i % n]`. Wall time is taken with a `Stopwatch`
(`elapsedMicroseconds`). Derived metrics:

- `ops/sec` = iterations / elapsed-seconds
- `mean us/scan` = elapsed-microseconds / iterations
- `MB/s` = total-corpus-bytes / elapsed-seconds, where total-corpus-bytes is
  the UTF-8 byte count summed across all 100,000 iterations
  (`bytesScanned(...)`)

The **same byte total** is used as the numerator for every row's `MB/s`, so the
MB/s column is directly comparable across scanners — it is a throughput proxy,
not a per-scanner input size.

### Single synchronous isolate

Every scanner is **pure and synchronous** (no I/O, no async, no shared mutable
state — enforced by the `Scanner` contract). The benchmark runs entirely on the
**main isolate**; there is no parallelism. A checksum folded from every result
(`fold()` sums `passed`, `findings.length`, and `text.length`) is printed at the
end so the optimizer cannot dead-code-eliminate the scan calls.

`SchemaValidator` is exercised at the **output** stage; all other scanners run
at the **input** stage. The pipeline row runs an `AiGuard` built from the seven
input-capable scanners, chained (each redacting scanner feeds its transformed
text to the next), short-circuiting at the first scanner that blocks.

## Measured results

| Scanner | ops/sec | mean us/scan | MB/s |
| --- | ---: | ---: | ---: |
| PiiScanner(redact) | 2476 | 403.89 | 2.80 |
| SecretScanner | 128035 | 7.81 | 144.60 |
| PromptInjectionScanner | 10208 | 97.96 | 11.53 |
| BannedTopicScanner | 361737 | 2.76 | 408.54 |
| BannedPatternScanner | 578513 | 1.73 | 653.36 |
| TokenLimitScanner(256) | 23274 | 42.97 | 26.29 |
| InvisibleTextScanner | 10899 | 91.75 | 12.31 |
| SchemaValidator | 257642 | 3.88 | 290.98 |
| AiGuard input pipeline (7 scanners) | 1793 | 557.68 | 2.03 |

**Environment:** Dart 3.12.0, Apple Silicon (arm64) macOS, single isolate.

> These numbers are **indicative and hardware-dependent**. Absolute figures will
> vary with CPU, Dart version, JIT vs AOT, and whether you run native or on the
> web (dart2js compiles to the host's JS engine). Treat the **relative** costs
> and the **order of magnitude** as the durable signal, not the exact digits.

## How to reproduce

```sh
dart run benchmark/benchmark.dart
```

The command prints the results table plus a checksum line reporting the
iteration count, warm-up count, corpus size, and bytes-per-corpus-cycle.

## Interpretation

All nine rows are **pure synchronous regex / string work** — no allocation of
threads, no I/O, no awaiting. The costs span roughly two orders of magnitude:

- **Fastest** (`BannedPatternScanner`, `BannedTopicScanner`,
  `SchemaValidator`): **~2–4 microseconds** per scan, 300–650 MB/s. These are a
  single literal/regex sweep or one `jsonDecode`.
- **Mid** (`SecretScanner`, `TokenLimitScanner`): **~8–43 us** per scan.
- **Slowest single scanner** (`PiiScanner(redact)`): **~400 us**, ~2.8 MB/s. It
  runs up to 11 patterns and, on redaction, rebuilds the whole string once per
  matching pattern (see `PERFORMANCE-AUDIT.md`). It dominates the pipeline.
- **Full input pipeline (7 scanners)**: **~558 us** per corpus item (~1.25 KB
  average), ~2.03 MB/s. It is only marginally slower than PII-redact alone
  because PII redaction is the dominant term and because the chain
  short-circuits when a blocking scanner (e.g. secrets) fires.

**Is it safe to run on the UI isolate?** For typical prompt sizes, **yes,
comfortably.** A typical chat prompt is well under a few KB. Even at the
conservative whole-pipeline rate of ~2 MB/s, a 2 KB prompt is scanned in **~1
millisecond**; most single scanners finish a 2 KB prompt in **tens of
microseconds**. That is far below a single 60 fps frame budget (~16 ms), so
guarding each prompt on the UI isolate is imperceptible.

Cost scales **linearly** with input size (every scanner is an O(n) sweep — see
the audit). Large inputs — pasted documents, uploaded files, RAG chunks in the
**tens to hundreds of KB** — should be offloaded with
`Isolate.run(() => guard.scanInput(text))`. `PERFORMANCE-AUDIT.md` gives a
concrete recommended maximum input size for the UI isolate and the offload
threshold.
