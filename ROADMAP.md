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

## Phase 0.7 — Provider wrappers

Make adoption frictionless — one import to guard any major LLM SDK.

### Packages

- [ ] `ai_guardrails_google` — `GuardedGenerativeModel` wrapping `google_generative_ai`
- [ ] `ai_guardrails_anthropic` — wrapper for `anthropic_sdk_dart`
- [ ] `ai_guardrails_langchain` — guardrails as a LangChain chain/tool

### Packaging strategy

Each wrapper is a **separate pub.dev package** with independent versioning.
Provider SDKs release on their own cadences — a breaking change in one must not
force a version bump on the others. Each depends on `ai_guardrails: ^0.x.0` as
a peer dependency.

Monorepo with path dependencies during development (Melos) is fine; publish as
independent packages. More pub.dev entries = more discoverability.

---

## Phase 0.7.5 — Tool-call validation

Agentic AI is the dominant growth pattern. Every framework (LangChain, CrewAI,
OpenAI Agents) emits tool calls — none validated by default.

### `ToolCallScanner`

- [ ] Validate LLM-emitted function calls before execution
- [ ] Tool name allowlist / denylist enforcement
- [ ] Argument validation against declared JSON Schema
- [ ] Injection detection in string arguments (reuses `CodeExecutionScanner` patterns)
- [ ] Recursive depth / nesting limits for tool chains

### Design constraint

Pure validation logic — no LLM or ML dependency. Fits the existing `Scanner`
contract. The schema definitions are caller-provided, not bundled.

---

## Phase 0.8 — Multi-turn context

Real LLM apps are conversational. Scanners today see one string in isolation.

### `GuardSession`

- [ ] Wraps `AiGuard` + mutable `_SessionState`
- [ ] Tracks finding counts, escalation level, turn history metadata across turns
- [ ] `session.run()` delegates to `guard.run()`, then applies escalation logic

### Escalation policies

- [ ] Configurable per-scanner: first violation = warn, second = block, third = terminate
- [ ] Accumulate findings by type across turns (`pii.*` count, `injection.*` count)
- [ ] "User asked 3 times for medical advice across 5 messages" as a signal

### Design constraint

`Scanner` stays stateless and synchronous — the composability guarantee is
non-negotiable. `GuardSession` is orchestration at the same level as `AiGuard`,
not a new scanner contract. No base class changes.

---

## Phase 0.8.5 — Retrieval / RAG stage

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

## Phase 0.8.7 — LLM-assisted scanners

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

## Phase 0.9 — Policy platform

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

## Phase 0.9.5 — Transform actions & padding attack scanner

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

## Explicitly deferred

These are conscious decisions, not oversights.

### On-device ML scanners

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

### Server mode / API gateway

Infrastructure concern — a FastAPI-style guardrails server (as NeMo offers) is
out of scope for a pub.dev package. A `shelf` middleware wrapper is a natural
companion package if demand emerges.

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
