# Changelog

## 1.3.0

- **`GuardTracer`** — abstract OTel-compatible tracing interface. `AiGuard`
  accepts an optional `GuardTracer` and emits per-request root spans, per-stage
  child spans, and per-scanner leaf spans with result/finding attributes. Zero
  cost when no tracer is configured. `StreamingAiGuard` forwards the tracer to
  its inner guard. `GuardSemantics` defines semantic convention attribute keys
  (`guardrail.scanner.name`, `guardrail.scan.result`, `guardrail.blocked`, etc.).
- **`GuardMessages`** — localised user-facing messages for 32 scanner types
  across 11 locales (EN, ES, PT, FR, DE, IT, JA, KO, ZH, AR, HI). Configurable
  via `customMessages` for per-scanner overrides. Resolution: custom → built-in
  locale → English fallback → generic. `ScanResultMessages` extension adds
  `ScanResult.userMessage({locale, messages})` for tree-shakeable convenience.
- **`ScannerPlugin`** / **`ScannerHub`** — plugin distribution convention for
  companion scanner packages. `ScannerPlugin` is the interface; `ScannerHub`
  installs plugins into a `ScannerRegistry`. Enables `ai_guardrails_scanners_*`
  companion packages without auto-discovery magic.

## 1.2.0

- **`EmbeddingGroundingScanner`** — semantic grounding via caller-provided
  `EmbeddingCallback`. Computes cosine similarity between output and source
  chunks; flags text below a configurable similarity threshold. Optional
  NLI-style entailment rescue via `LlmCallback` for edge cases where
  paraphrased text fails embedding similarity. Upgrades the keyword-overlap
  `GroundingScanner` (0.4) with vector-level depth. Finding type:
  `grounding.low_similarity`. Output-stage only.
- **`EmbeddingCallback`** — `typedef EmbeddingCallback = Future<List<double>>
  Function(String text)`. Caller-provided embedding interface. The package
  never imports an embedding SDK.
- **`EmbeddingDependent`** mixin — scanners declare embedding dependency;
  `AiGuard` validates and injects at construction. Follows the same pattern
  as `LlmDependent`.
- **`AiGuard.embeddingCallback`** — optional named parameter on `AiGuard()`,
  `AiGuard.fromConfig()`. Only required when the scanner chain contains
  `EmbeddingDependent` scanners.
- **`GuardCache`** — configurable cache for `LlmCallback` and
  `EmbeddingCallback` results. Content-hash keyed, TTL-based expiry.
  `wrapLlm()` and `wrapEmbedding()` return cached callback wrappers.
  Tracks hit/miss stats via `hits`, `misses`, `hitRate`. In-memory default
  via `InMemoryCache` (LRU eviction); pluggable via `CacheBackend` interface.
- **`GuardProbe`** — proactive red-teaming tool that attacks the scanner
  chain with adversarial inputs per scanner type. Reports `ProbeResult`
  per scanner (bypass rate, caught count, bypassed inputs) and an overall
  `ProbeReport.resilienceScore`. Probe sets cover PII evasion, injection
  role-play, secret obfuscation, invisible text, URL exploits, code
  execution indirection, padding attacks, and SQL injection.
- 31 built-in scanners total.

## 1.1.0

- **Format validators** — 6 pure-Dart output validators:
  `JsonValidator` (syntax + depth/array/key limits), `HtmlValidator` (tag/attribute
  allowlists, event handler & javascript: URI blocking), `SqlValidator` (statement-type
  allowlist, default SELECT-only), `UrlFormatValidator` (protocol/domain allowlists,
  credential blocking), `RangeValidator` (numeric bounds + string length),
  `ChoicesValidator` (output must be one of N values).
- **`TopicAllowlistScanner`** — positive topic enforcement ("you may ONLY discuss
  X, Y, Z"). Keyword mode (zero deps) or LLM-assisted semantic mode via
  `LlmCallback`. Complements `BannedTopicScanner` (negative blocklist).
- **Brand safety scanners** — `CompetitorMentionScanner` (configurable competitor
  name/product lists with redact/hash/block/warn), `BiasScanner` (demographic bias
  heuristics + optional LLM deep analysis), `PolitenessScanner` (tone register
  detection: formal/neutral/casual), `ReadingLevelScanner` (Flesch-Kincaid +
  Coleman-Liau grade level enforcement).
- All 11 scanners registered in `ScannerRegistry` with config-driven construction.
- 30 built-in scanners total.

## 1.0.0

- **`OnFailAction`** — configurable per-scanner failure strategies at the
  orchestrator level: `block`, `warn`, `filter`, `fix`, `reask`, `refrain`,
  `noop`. Configure via `AiGuard(onFailActions: {'pii': OnFailAction.warn})`
  or JSON config `"onFailActions": {"pii": "warn"}`. Overrides the scanner's
  own pass/block decision. `filter` clears text, `fix` applies
  `ScanResult.suggestedFix`, `refrain` returns empty output (graceful
  refusal), `noop` skips the scanner entirely.
- **`GuardedLlmCall`** — corrective retry wrapper around `AiGuard`. When
  output scanners trigger `OnFailAction.reask`, injects error feedback into
  the prompt and retries the LLM call up to `maxReasks` times. Custom retry
  prompt via `retryPromptBuilder`. Non-reask failures return immediately.
- **`ToolOutputScanner`** — detects XSS, server-side template injection
  (SSTI), path traversal, and SSRF indicators in tool execution results.
  Walks JSON structures to scan all string values. Complements `ToolCallScanner`
  (which validates tool inputs) by scanning tool outputs — critical for agentic
  pipelines where tools return untrusted data.
- **`AiGuard.runToolOutputStage()`** — scans tool execution results through
  input scanners before feeding them back to the LLM or user. Returns
  `ToolOutputResult` with per-tool pass/fail, processed content, and findings.
- `ScanResult.suggestedFix` — optional replacement text for `OnFailAction.fix`.
- `GuardOutcome.failAction` — the `OnFailAction` that stopped the pipeline.

## 0.9.1

- **`GuardAction.transform`** — new action for scanners that rewrite content
  permanently (strip dangerous URLs, sanitise code blocks). Scanners modify
  text and record what they changed in `ScanResult.transformations`
  (original → replacement). Unlike `redactionMap`, transforms are NOT reversed
  in output — they are permanent sanitisation. `ScanResult.transform()` named
  constructor parallels `.block()` and `.warn()`. `GuardOutcome.transformations`
  exposes the merged map across both pipelines.
- **`PaddingAttackScanner`** — detects context-exhaustion padding via two
  heuristics: Shannon entropy floor (default 3.0 bits/char) flags low-entropy
  padding, and single-char run ratio (default 10%) catches repeated-character
  attacks. Configurable `entropyFloor`, `maxRunRatio`, `minRunLength`.
  Complements `TokenLimitScanner` (size) and `RepetitionScanner` (n-grams)
  with character-level information-theoretic analysis. Input stage only.

## 0.9.0

- **`ScannerRegistry`** — named scanner registration for dynamic lookup and
  config-driven loading. Global singleton with all 17 built-in scanners
  auto-registered. Register custom scanners with `register()` (factory) or
  `registerInstance()` (pre-built). `AiGuard.fromConfig()` now accepts an
  optional `registry` parameter and supports scanner names as strings alongside
  inline config objects.
- **Policy DSL** — declarative post-scan rules evaluated against accumulated
  findings. Supports `count`, `maxScore`, `totalScore` aggregations with
  comparison operators (`gt`, `gte`, `lt`, `lte`, `eq`), plus `any`/`none`
  shortcuts. Glob-pattern matching on finding types (`pii.*`, `*`).
  Rules are specified in JSON (`{"when": {"count": "pii.*", "gt": 3}, "then": "block"}`)
  and parsed by `AiGuard.fromConfig()`.
- **`PolicyProfile`** — pre-built scanner + threshold bundles for four industry
  verticals: `healthcare` (HIPAA-aligned PII), `finance` (PCI patterns),
  `education` (URL/code filtering), `enterprise` (DLP defaults). Each profile
  is an overridable starting point — call `toGuard()` or `toGuardWith(overrides)`.
- **Red-team test corpus** — 62 hand-written adversarial prompts at
  `test/fixtures/redteam/corpus.json` covering prompt injection, PII,
  secrets, code execution, URL attacks, invisible text, repetition, and
  benign cases. Apache-2.0 licensed, no scraped content.
- **`GuardBenchmark`** — precision/recall/F1 harness for evaluating scanner
  chains against a labeled corpus. Per-scanner finding breakdown and
  per-category accuracy metrics. Ships with the red-team corpus as sample data.

## 0.8.4

- **`HallucinationScanner`** — SelfCheckGPT-style cross-completion consistency
  check. Generates N alternative completions via `LlmCallback`, then asks the
  LLM to identify claims in the original that contradict the samples.
  Configurable `sampleCount` (default 3) and `action` (default `warn`).
  Finding type: `hallucination.inconsistent_claim`.
- **`FactCheckScanner`** — NLI-style output-vs-context verification. Prompts
  the caller's LLM to judge whether output follows from a provided source
  context. Returns `supported` / `contradicted` / `unsupported` verdicts.
  Complements `GroundingScanner` (keyword-overlap) with semantic judgment.
  Finding types: `factcheck.contradiction`, `factcheck.unsupported`.
- **`TopicSafetyScanner`** — LLM-judged topic adherence. Supports allow-lists,
  deny-lists, or both. Runs on both input and output stages.
  Finding types: `topic_safety.off_topic`, `topic_safety.forbidden_topic`.

## 0.8.3

- **`LlmCallback`** — `typedef LlmCallback = Future<String> Function(String prompt)`.
  Caller-provided LLM interface for semantic scanners. The package never imports
  an LLM SDK; the callback is the abstraction boundary.
- **`LlmDependent`** mixin — scanners that need LLM judgment mix this in.
  `AiGuard` validates at construction that the callback is provided and injects
  it automatically.
- **`AiGuard.llmCallback`** — optional named parameter on `AiGuard()`,
  `AiGuard.fromConfig()`, and `StreamingAiGuard()`. Only required when the
  scanner chain contains `LlmDependent` scanners.

## 0.8.2

- **`AiGuard.runRetrievalStage()`** — new pipeline stage for RAG applications.
  Scans a list of retrieved chunks through `inputScanners` independently before
  prompt assembly. Poisoned or policy-violating chunks are dropped; clean ones
  pass through (possibly redacted). No new scanners required — reuses the
  existing input scanner chain.
- **`ChunkResult`** — per-chunk scan outcome: original text, processed text,
  pass/fail, drop reason, and per-scanner results.
- **`RetrievalResult`** — wraps all chunk results with convenience getters:
  `.accepted` (processed text of passing chunks), `.dropped` (blocked chunk
  results), `.allFindings` (findings aggregated across all chunks).

## 0.8.1

- **`EscalationRule`** — per-finding-type escalation thresholds. Attach to
  `EscalationPolicy.typeRules` keyed by exact type (`pii.email`) or glob
  pattern (`pii.*`) to override global thresholds for specific finding
  categories.
- **`EscalationPolicy.window`** — sliding-window escalation. When set, only
  the last N turns count toward thresholds — older violations decay.
  Terminated sessions with a window recover after enough cooldown turns.
  Without a window, escalation remains monotonic (existing behavior).
- **`GuardSession.onEscalation`** — callback fires on every escalation level
  change (including de-escalation with window).
- **`GuardSession.toJson()` / `GuardSession.restore()`** — persist session
  state across server restarts. Serializes turn count, finding/scanner counts,
  per-turn snapshots, and escalation level. Text content is never included.

## 0.8.0

- **`GuardSession`** — stateful multi-turn wrapper around `AiGuard`. Tracks
  turn count, accumulates per-scanner and per-finding-type counts across a
  conversation, exposes `turnHistory` and `lastOutcome`.
- **`EscalationPolicy`** — configurable escalation with `blockThreshold` and
  `terminateThreshold`. Three levels: `warn` (default) → `block` (force-block
  turns with findings) → `terminate` (refuse all further runs). No policy =
  no escalation (backward-compatible).
- **`EscalationLevel`** enum — `warn`, `block`, `terminate`.

## 0.7.5

- **`ToolCallScanner`** — validates LLM-emitted tool/function calls for agentic
  pipelines. Four layers: name allow/deny lists, per-tool argument JSON Schema
  validation, injection detection (shell/SQL/code/prompt in string args), and
  recursive depth/circular-reference limits. Accepts single objects or arrays.
  Malformed JSON is blocked (fail-closed).
- **`ToolCall`** — data class for parsed tool calls with `fromJson`/`toJson`
  and `parseToolCalls` static helper.
- **`CodePattern`** / `CodeExecutionScanner.patterns` — code-execution patterns
  now public for reuse by downstream scanners.

## 0.7.0

- **`AsyncScanner`** — async counterpart to `Scanner` for scanners that need
  I/O or model inference (e.g. on-device ML classifiers). Both now implement
  a shared `ScannerBase` sealed class so `AiGuard` accepts either in one list.
- **`ScanResult.block()` / `.warn()`** — named constructors that parallel the
  existing `.pass()`, reducing boilerplate in custom scanners.
- **Breaking**: `AiGuard.scanInput`, `scanOutput`, `runInputStage`,
  `runOutputStage`, and `StreamingAiGuard.scanInput` now return `Future`s.
  `inputScanners`/`outputScanners` are now typed `List<ScannerBase>`.

## 0.6.0

- **International PII expansion** — 6 new locales: Brazil (CPF, CNPJ), Mexico
  (CURP, RFC), Japan (My Number), South Korea (RRN), Canada (SIN with
  Luhn validation), Australia (TFN, Medicare). Each with country-specific
  phone patterns.
- **EU country-specific phones** — replaced the single generic EU phone regex
  with dedicated patterns for UK (+44), Germany (+49), France (+33), Italy
  (+39), and Spain (+34). Reduces false positives on partial matches.
- **RTL text verification** — verified all scanners produce correct offsets on
  Arabic and Hebrew text with embedded PII. Redaction preserves RTL structure.
- **`PiiLocale` enum expanded** — added `brazil`, `mexico`, `japan`,
  `southKorea`, `canada`, `australia`. `fromConfig` supports all locale names.
- **`PiiPattern.luhnMinDigits`** — per-pattern Luhn minimum digit count
  (default 12 for credit cards, 9 for Canadian SIN).

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
