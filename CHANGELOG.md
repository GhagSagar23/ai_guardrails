# Changelog

## 0.5.0

- **`GuardLog`** — structured, JSON-serializable audit record of every scan.
  Contains scanner chain results, findings, text hashes (never raw text), and
  timestamps. Wire to any logging backend via `AiGuard.onScan` callback.
- **`GuardMetrics`** — per-run metrics snapshot: total/input/output duration,
  block status, finding counts, per-scanner breakdown. Wire to dashboards via
  `AiGuard.onMetrics` callback.
- **`AiGuard.fromConfig()`** — build a complete `AiGuard` from a
  `Map<String, dynamic>` (JSON). Declare scanner chains, thresholds, and
  actions without code changes. Deploy policy updates without recompilation.
  Supports all 13 scanner types.

## 0.4.0

- **`StreamingAiGuard`** — streaming wrapper for chunked LLM responses. Buffers
  incoming chunks, splits at configurable boundaries (default: newline), runs
  output scanners on each segment, yields `GuardedChunk`s. Terminates the stream
  on block. PII rehydration works per-chunk. Input scanning is identical to
  `AiGuard`. Scanners see each segment independently — use `AiGuard` for
  full-output scanning (e.g. `SchemaValidator`) after the stream completes.
- **`GroundingScanner`** — checks whether LLM output is grounded in a provided
  source context via keyword-overlap heuristic. Extracts content words (non-stop-
  words), computes overlap ratio, flags text when grounding falls below threshold.
  Finding type: `grounding.unsupported_claim`. Default action: `warn`.
- **`StageRun`** — exposed as public API for `StreamingAiGuard` and advanced
  use cases. `AiGuard.runInputStage()` and `AiGuard.runOutputStage()` return
  full stage results including redaction maps.

## 0.3.0

- **`UrlScanner`** — detects suspicious URLs: IP-literal hosts, `data:`/`javascript:`
  URIs, phishing TLDs (`.tk`, `.buzz`, `.zip`, etc.), URL shorteners, punycode
  (homograph attacks), and embedded credentials. Configurable categories via
  `UrlCategory` enum. Runs on input and output.
- **`LanguageScanner`** — script-detection heuristic using Unicode character-class
  ratios (Latin, Cyrillic, CJK, Devanagari, Arabic, Greek, Hangul, Hiragana,
  Katakana, Thai). Flags text when the expected-script fraction falls below a
  threshold. Catches cross-script prompt injection and unexpected language switches.
- **`CodeExecutionScanner`** — detects dangerous patterns in generated code: shell
  commands (`rm -rf`, `curl|sh`, `dd`, `chmod 777`), SQL destruction (`DROP TABLE`,
  `TRUNCATE`, `DELETE FROM`), code injection (`eval`, `exec`, `os.system`,
  `subprocess`, `Process.start`), and filesystem deletion (`shutil.rmtree`,
  `unlink`). Configurable categories via `CodeCategory` enum. Output-stage only.

## 0.2.0

- **PII round-trip rehydration** — `AiGuard.run()` now automatically restores
  redacted PII in the LLM output. Placeholders like `[EMAIL_1]` in the model
  response are replaced with the original values so `outcome.output` reads
  naturally. `outcome.rawOutput` preserves the pre-rehydration text;
  `outcome.piiMap` exposes the placeholder→original map for manual control.
- **Numbered redaction placeholders** — `PiiScanner` now produces unique tokens
  per occurrence (`[EMAIL_1]`, `[EMAIL_2]`) instead of a shared `[EMAIL]`.
  Hash-mode placeholders (`[EMAIL:a1b2c3]`) are unchanged (already unique).
- **`ScanResult.redactionMap`** — any scanner that transforms text can now
  populate a `Map<String, String>` of token→original. `AiGuard` merges maps
  across chained scanners.
- **`RepetitionScanner`** — detects degenerate model output (looping / repeated
  phrases) via word-level n-gram frequency analysis. Configurable n-gram size
  and threshold; output-stage only.

## 0.1.0

Initial release.

- `AiGuard` orchestrator with chained input/output pipelines: redacting scanners
  chain (each sees the previous scanner's transformed text) and the pipeline
  stops at the first scanner that blocks.
- Eight scanners:
  - `PiiScanner` — PII detection/redaction across US/EU/India locales, with a
    Luhn check on credit-card matches.
  - `SecretScanner` — API keys, tokens, and private-key blocks.
  - `PromptInjectionScanner` — heuristic weighted scoring of injection signals.
  - `BannedTopicScanner` — word-boundary topic matching.
  - `BannedPatternScanner` — arbitrary `Pattern`/`RegExp` matching.
  - `TokenLimitScanner` — approximate token-count ceiling.
  - `InvisibleTextScanner` — zero-width, bidi, soft-hyphen, and tag-char removal.
  - `SchemaValidator` — minimal JSON-Schema-subset validation of model output.
- Pure Dart, on-device, zero runtime dependencies.
