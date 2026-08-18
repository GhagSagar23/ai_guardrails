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

---

## Contributing to the roadmap

Every item above is a valid contribution target. The process:

1. [Open an issue](https://github.com/GhagSagar23/ai_guardrails/issues) referencing
   the roadmap item (e.g. "Implement `UrlScanner` — Phase 0.3")
2. Discuss scope and approach in the issue
3. Fork, implement, PR to `master`

Self-contained items (new PII locale, new scanner, provider wrapper) are ideal
first contributions. Cross-cutting items (streaming, policy engine) benefit from
design discussion in the issue first.

### Guiding principles

- **Zero runtime dependencies** — the core package never adds one
- **Pure Dart** — runs on all platforms, including web and UI isolate
- **Scanner contract is frozen** — `Scanner.scan()` stays pure and synchronous
- **Shortest working diff** — new features are additive, not refactors
- **Tests are mandatory** — every scanner ships with comprehensive tests
- **Documented limits** — heuristic scanners have known FP/FN; document them honestly
