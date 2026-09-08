# Roadmap

The path from "scanner collection" to "the guardrails platform for Dart."

Each phase builds on the last. Phases are shippable independently — no phase
blocks on a later one. Contributions welcome on any item; see
[CONTRIBUTING.md](CONTRIBUTING.md) for the issue-first workflow.

---

## Shipped

### 0.1 — Core scanners

8 heuristic scanners, `AiGuard` orchestrator, zero runtime dependencies.

- `PiiScanner` (US/EU/India, Luhn-checked credit cards)
- `SecretScanner` (AWS, GCP, OpenAI, Slack, GitHub, JWTs, PEM blocks)
- `PromptInjectionScanner` (weighted heuristic scoring)
- `InvisibleTextScanner` (zero-width, bidi, tag chars)
- `BannedTopicScanner`, `BannedPatternScanner`
- `TokenLimitScanner`, `SchemaValidator`

### 0.2 — PII round-trip & output quality

- PII round-trip rehydration — `AiGuard` auto-restores redacted PII in output
- Numbered placeholders (`[EMAIL_1]`, `[EMAIL_2]`) for unique mapping
- `ScanResult.redactionMap` — generic token→original mechanism for any scanner
- `RepetitionScanner` — word n-gram degeneration detector

### 0.3 — Security & language safety

- `UrlScanner` — IP-literal, data/JS URIs, phishing TLDs, shorteners, punycode, credentials
- `LanguageScanner` — Unicode script-ratio heuristic (10 writing systems)
- `CodeExecutionScanner` — shell, SQL, injection, filesystem danger patterns

### 0.4 — Streaming & grounding

- `StreamingAiGuard` — streaming wrapper for chunked LLM responses with per-segment scanning
- `GroundingScanner` — keyword-overlap grounding checker against source context
- `StageRun` / `AiGuard.runInputStage()` / `runOutputStage()` — public stage-level API

### 0.5 — Enterprise observability

- `GuardLog` — structured, JSON-serializable audit record (text hashes, never raw text)
- `GuardMetrics` — per-run timing and finding-count snapshot via `onMetrics` callback
- `AiGuard.fromConfig()` — build scanner chains from JSON config without code changes

### 0.6 — International PII expansion

- 6 new locales: Brazil (CPF, CNPJ), Mexico (CURP, RFC), Japan (My Number),
  South Korea (RRN), Canada (SIN, Luhn-validated), Australia (TFN, Medicare)
- EU country-specific phones: UK (+44), Germany (+49), France (+33), Italy (+39), Spain (+34)
- RTL text (Arabic, Hebrew) verified with correct offsets and redaction

---

### 0.7 — Provider wrappers (packaging)

Separate pub.dev packages for frictionless SDK adoption. Independent versioning
so a provider SDK breaking change doesn't cascade.

- `ai_guardrails_google` — `GuardedGenerativeModel` wrapping `google_generative_ai`
- `ai_guardrails_anthropic` — wrapper for `anthropic_sdk_dart`
- `ai_guardrails_langchain` — guardrails as a LangChain chain/tool

### 0.7 — Async scanner contract

- `AsyncScanner` — async counterpart for scanners needing I/O or model inference
- `ScannerBase` sealed class unifying `Scanner` / `AsyncScanner`
- `ScanResult.block()` / `.warn()` named constructors
- **Breaking**: pipeline methods now return `Future`s

### 0.7.5 — Tool-call validation

- `ToolCallScanner` — name allow/deny, per-tool JSON Schema validation,
  injection detection, recursive depth / nesting limits
- `ToolCall` data class with `fromJson`/`toJson`/`parseToolCalls`
- `CodePattern` / `CodeExecutionScanner.patterns` made public for reuse

### 0.8 — Multi-turn context: GuardSession + escalation

- `GuardSession` wrapping `AiGuard` + mutable session state
- Turn history, per-type / per-scanner finding accumulation
- `EscalationPolicy` with global `blockThreshold`/`terminateThreshold`
- `EscalationLevel` enum: warn → block → terminate

### 0.8.1 — Multi-turn context: typed rules, windows, persistence

- `EscalationRule` — per-finding-type thresholds (`pii.*` → block at 2)
- `EscalationPolicy.typeRules` — glob-pattern matching (`prefix.*`)
- `EscalationPolicy.window` — sliding window: only last N turns count,
  old violations decay, terminated sessions can cool down
- `GuardSession.onEscalation` — callback on level transitions
- `GuardSession.toJson()` / `GuardSession.restore()` — persist session
  state across server restarts (text excluded, escalation metadata only)

### Design constraint

`Scanner` stays stateless and synchronous — the composability guarantee is
non-negotiable. `GuardSession` is orchestration at the same level as `AiGuard`,
not a new scanner contract. No base class changes.

---

## Phase 0.8.2 — Retrieval / RAG stage

RAG apps assemble prompts from retrieved documents. Poisoned or irrelevant
chunks entering the prompt is a real attack surface.

### `AiGuard.runRetrievalStage()`

- [ ] New pipeline stage: scan retrieved chunks before prompt assembly
- [ ] Reuses existing scanners (PII in docs, injection in chunks, secrets in KB content)
- [ ] Per-chunk pass/fail with reason — drop poisoned chunks, keep clean ones
- [ ] Optional relevance threshold via `GroundingScanner`

### Design constraint

No new scanners required — the stage is a pipeline addition, not a scanner
addition. Chunks are scanned independently; the stage returns a filtered list.

---

## Phase 0.8.3 — LLM-assisted scanners

The heuristic scanners cover pattern-matching. For semantic judgments
(hallucination, factual consistency, topic adherence), the user's own LLM is
the detection engine.

**This is distinct from on-device ML** (which remains deferred). LLM-assisted
scanners are prompt templates + orchestration logic executed via a
caller-provided callback. No model weights, no FFI, no tflite.

### `LlmCallback`

- [ ] `typedef LlmCallback = Future<String> Function(String prompt)`
- [ ] User provides their own LLM call — package provides the prompt templates
- [ ] Injected at `AiGuard` construction, passed to scanners that need it

### Scanners

- [ ] `HallucinationScanner` — sample N completions, cross-check consistency (SelfCheckGPT-style)
- [ ] `FactCheckScanner` — NLI-style "does the output follow from the provided context?"
- [ ] `TopicSafetyScanner` — LLM judges whether output stays within declared topic bounds

### Design constraint

`Scanner.scan()` stays pure and synchronous for heuristic scanners. LLM-assisted
scanners implement an `AsyncScanner` variant (already supported by the pipeline).
The `LlmCallback` is injected, not owned — the package never imports an LLM SDK.

---

## Phase 0.9.0 — Policy platform

The jump from "scanner collection" to "guardrails platform."

### Policy DSL

- [ ] Declarative rules: `when: findings.count('pii.*') > 3, then: block`
- [ ] Compose scanners into policies without writing Dart code
- [ ] JSON-based (consistent with 0.5 config format)

### Policy profiles

- [ ] Pre-built bundles: `healthcare` (strict PII, HIPAA-aligned), `finance` (PCI patterns),
      `education` (age-appropriate), `enterprise` (data loss prevention)
- [ ] Users pick a profile and get sensible scanner + threshold defaults
- [ ] Profiles are overridable — starting points, not locked configurations

### Scanner registry

- [ ] `AiGuard.register('my_scanner', MyScanner())` with named lookup
- [ ] Policies reference scanners by name, not by import
- [ ] Enables dynamic scanner loading from config

### Red-team test corpus

- [ ] ~50–100 adversarial prompts for validating scanner coverage
- [ ] Ships as `test/fixtures/redteam/` with per-source `LICENSE` files
- [ ] Sources: OWASP LLM Top 10 examples (public), academic papers with
      CC/MIT-licensed prompts, hand-written prompts under Apache-2.0
- [ ] Never: scraped Reddit/Discord/Twitter content (unclear licensing)

### Benchmarking harness

- [ ] `GuardBenchmark` — users run their own prompt corpus through the scanner chain
- [ ] Outputs precision/recall report per scanner
- [ ] Ships with the red-team corpus as sample data

---

## Phase 0.9.1 — Transform actions & padding attack scanner

Move beyond detect-and-block — allow scanners to actively sanitise content.

### Transform actions

- [ ] `ScanAction.transform` — scanners can suggest content rewrites (beyond PII redaction)
- [ ] Strip dangerous URLs from output, sanitise code blocks, rewrite tool-call arguments
- [ ] Scanner contract unchanged — transforms are returned as `ScanResult` metadata, applied by orchestrator

### `PaddingAttackScanner`

- [ ] Shannon entropy floor (detect low-entropy padding designed to exhaust context)
- [ ] Single-char run ratio detection
- [ ] Complements existing `TokenLimitScanner` (size) and `RepetitionScanner` (n-grams)

### Design constraint

Pure math — no dependencies. The transform mechanism is orchestrator-level
(like PII rehydration), not a scanner contract change.

---

## Phase 1.0 — Active guardrails

The jump from "detect and report" to "detect and correct." These features turn
ai_guardrails from a scanner collection into an active guardrail that fixes
problems without the caller writing retry logic.

### Phase 1.0.0 — Configurable on-fail actions per scanner

- [ ] `OnFailAction` enum: `block`, `warn`, `filter`, `fix`, `reask`, `refrain`, `noop`
- [ ] Per-scanner action configuration at `AiGuard` construction
- [ ] `ScanResult` carries suggested fix metadata when action is `fix`
- [ ] Orchestrator applies action (filter removes content, refrain returns empty, etc.)

### Phase 1.0.1 — Re-ask / corrective retry loop

- [ ] `GuardedLlmCall` wrapper — takes `LlmCallback` + `AiGuard`, auto-retries on failure
- [ ] Configurable `maxReasks` with error feedback injected into retry prompt
- [ ] Works with both sync and streaming pipelines
- [ ] Requires `OnFailAction.reask` from Phase 1.0.0

### Phase 1.0.2 — Tool execution output scanning

- [ ] `AiGuard.runToolOutputStage()` — scan tool *results* (not just tool *calls*)
- [ ] SQL injection, XSS, Jinja template injection detection in tool responses
- [ ] Complements `ToolCallScanner` (0.7.5) which validates inputs only
- [ ] Critical for agentic pipelines where tools return untrusted data

### Design constraint

`OnFailAction` is orchestrator-level, like `EscalationPolicy`. Scanners remain
stateless — they return findings, the orchestrator decides the action. The re-ask
loop is a convenience wrapper, not a pipeline change.

---

## Phase 1.1 — Format & topic validators

Pure-Dart validators for common output format and topic constraints.
Ideal community contribution targets.

### Phase 1.1.0 — Format validators

- [ ] `JsonValidator` — well-formed JSON beyond schema (syntax, depth limits)
- [ ] `HtmlValidator` — tag allowlists, attribute sanitisation
- [ ] `SqlValidator` — statement type allowlist (SELECT only, no DROP/ALTER)
- [ ] `UrlFormatValidator` — protocol allowlist, domain allowlist, no credentials
- [ ] `RangeValidator` — numeric bounds, string length, date ranges
- [ ] `ChoicesValidator` — output must be one of N allowed values

### Phase 1.1.1 — Positive topic enforcement

- [ ] `TopicAllowlistScanner` — "you may ONLY discuss X, Y, Z"
- [ ] Keyword + semantic similarity (via `LlmCallback` for semantic mode)
- [ ] Complements `BannedTopicScanner` (negative blocklist) with positive allowlist
- [ ] Configurable strictness: keyword-only (zero deps) or LLM-assisted

### Phase 1.1.2 — Brand safety scanners

- [ ] `CompetitorMentionScanner` — configurable competitor name/product lists
- [ ] `BiasScanner` — demographic bias indicators in generated text
- [ ] `PolitenessScanner` — tone/register checks (formal, neutral, casual)
- [ ] `ReadingLevelScanner` — Flesch-Kincaid / Coleman-Liau grade level enforcement

### Design constraint

All format validators are pure Dart, zero dependencies. Brand safety scanners
may optionally use `LlmCallback` for deeper analysis but must have a heuristic
fallback that works without it.

---

## Phase 1.2 — Advanced provenance & intelligence

Upgrades to grounding/fact-checking and adversarial testing tooling.

### Phase 1.2.0 — Embedding/NLI-based provenance

- [ ] `EmbeddingGroundingScanner` — cosine similarity between output and source chunks
- [ ] Accepts caller-provided embedding callback (like `LlmCallback` pattern)
- [ ] NLI-style entailment check: "does the output follow from the context?"
- [ ] Upgrades keyword-overlap `GroundingScanner` (0.4) with semantic depth

### Phase 1.2.1 — LLM pipeline caching

- [ ] `GuardCache` — configurable cache for `LlmCallback` and `AsyncScanner` results
- [ ] Content-hash keyed, TTL-based expiry
- [ ] Critical once LLM-assisted scanners (0.8.3) land — repeated similar scans are expensive
- [ ] In-memory default, pluggable backend interface

### Phase 1.2.2 — LLM vulnerability scanning

- [ ] `GuardProbe` — proactive red-teaming tool that attacks the scanner chain
- [ ] Generates adversarial prompts targeting each scanner's known weaknesses
- [ ] Reports bypass rate per scanner and overall pipeline resilience score
- [ ] Extends benchmark harness (0.9.0) from "measure" into "attack"

### Design constraint

Embedding callback follows the same injection pattern as `LlmCallback` — the
package never imports an embedding SDK. Cache is in-memory by default; users
bring their own persistence layer.

---

## Phase 1.3 — Observability & UX

Production-grade observability and end-user-facing message support.

### Phase 1.3.0 — OpenTelemetry tracing

- [ ] `GuardTracer` — per-request spans with scanner-level child spans
- [ ] Trace ID propagation through pipeline stages
- [ ] Latency distributions, error rates, token usage attributes
- [ ] OTel semantic conventions for LLM guardrail operations
- [ ] Pluggable exporter interface (caller provides the OTel SDK)

### Phase 1.3.1 — Multilingual refusal/feedback messages

- [ ] `GuardMessages` — localised user-facing messages per finding type
- [ ] Ships with 10+ locales (EN, ES, PT, FR, DE, IT, JA, KO, ZH, AR, HI)
- [ ] Configurable per-scanner message templates
- [ ] `ScanResult.userMessage(locale)` convenience accessor

### Phase 1.3.2 — Scanner hub / plugin distribution

- [ ] Scanner distribution story via pub.dev companion packages
- [ ] `ai_guardrails_scanners_brand`, `ai_guardrails_scanners_medical`, etc.
- [ ] Registry auto-discovers installed scanner packages
- [ ] Extends scanner registry (0.9.0) with package-level plugin loading

### Design constraint

OTel integration is optional — users who don't use OTel pay zero cost.
The package provides the instrumentation points; the OTel SDK is the caller's
dependency. Message bundles are tree-shaken — import only the locales you need.

---

## Phase 1.4 — Infrastructure & ecosystem

Architectural expansions beyond the core library. These are companion
packages or major scope changes — evaluated based on community demand.

### Phase 1.4.0 — Guard server (shelf middleware)

- [ ] `ai_guardrails_server` — `shelf` middleware wrapping `AiGuard`
- [ ] OpenAI-compatible `/v1/chat/completions` endpoint with guard injection
- [ ] Docker-ready, configurable via JSON policy files (0.9.0 format)
- [ ] Standalone deployment for teams that want guardrails as infrastructure

### Phase 1.4.1 — Remote validation / hosted ML connectors

- [ ] Connector interface for third-party moderation APIs
- [ ] `ai_guardrails_google` — Google Cloud Text Moderation
- [ ] `ai_guardrails_perspective` — Perspective API (toxicity scoring)
- [ ] Companion packages, never in core — keeps zero-dependency guarantee

### Phase 1.4.2 — Conversational flow management

- [ ] Declarative flow definitions for multi-turn conversations
- [ ] Canonical form mapping (user intent → allowed response paths)
- [ ] Topic rail enforcement at the conversation level (not just per-turn)
- [ ] Significant scope expansion — evaluate community demand before committing

### Design constraint

All Phase 1.4 items are companion packages with their own versioning.
Core `ai_guardrails` never gains a runtime dependency. Server mode uses
`shelf` (Dart's standard HTTP server library). Remote connectors are
optional installs.

---

## Explicitly deferred

These are conscious decisions, not oversights.

### On-device ML scanners (Phase 2.0.0)

Not viable in pure Dart today. `tflite_flutter` is Flutter-only (not pure Dart),
ONNX Runtime has no Dart binding, and shipping FFI-bundled native libs for a
pub.dev package is a maintenance nightmare across 6+ platforms. The heuristic
scanners cover the 90% case. Revisit when the Dart ML inference ecosystem matures.

### Toxicity word lists

Legal and cultural minefield. Better left to users who know their domain. The
package provides the mechanism (`BannedTopicScanner`, `BannedPatternScanner`) —
the word lists are the caller's responsibility.

### Rate limiting / quota enforcement

Infrastructure, not guardrails. Mixing concerns weakens the package identity.
Use `shelf_rate_limiter` or equivalent.

### ~~Server mode / API gateway~~ → Planned (Phase 1.4.0)

Moved from deferred to roadmap as a `shelf` middleware companion package.

### Vector DB / embedding integrations

Separate packages with their own versioning. The core package provides the
scanning pipeline; retrieval and embedding are the caller's domain.

---

## Contributing to the roadmap

Every item above is a valid contribution target. The process:

1. [Open an issue](https://github.com/GhagSagar23/ai_guardrails/issues) referencing
   the roadmap item (e.g. "Implement `UrlScanner` — Phase 0.3")
2. Discuss scope and approach in the issue
3. Fork, implement, PR to `master`

Self-contained items (new PII locale, new scanner, provider wrapper, tool-call
validator) are ideal first contributions. Cross-cutting items (LLM-assisted
scanners, retrieval stage, policy engine) benefit from design discussion in the
issue first.

### Guiding principles

- **Zero runtime dependencies** — the core package never adds one
- **Pure Dart** — runs on all platforms, including web and UI isolate
- **Scanner contract is frozen** — `Scanner.scan()` stays pure and synchronous
- **Shortest working diff** — new features are additive, not refactors
- **Tests are mandatory** — every scanner ships with comprehensive tests
- **Documented limits** — heuristic scanners have known FP/FN; document them honestly
