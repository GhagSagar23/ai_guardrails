# Changelog

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
