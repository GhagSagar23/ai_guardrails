# Accuracy & limitations

Back to [README](../README.md).

---

These scanners are **regex/heuristic and context-free** — they match the *shape* of data,
not its meaning. That's what buys the speed and the zero dependencies; it also has two
inherent edges worth designing around.

## False positives — ambiguity no regex can resolve

Some strings are byte-identical to real PII without their surrounding context, so they match:

| Input | Reported as | Why it's unavoidable |
| --- | --- | --- |
| `123-45-6789` | `pii.ssn` | any 9-digit dashed number has the SSN shape |
| `10.0.0.256` | `pii.ip` | matches dotted-quad shape even though `.256` isn't a valid octet |
| a valid-Luhn 16-digit run (e.g. an order id) | `pii.credit_card` | Luhn passes; only context says it isn't a card |

Disambiguating these needs surrounding-context / allow-listing, which this package
deliberately does not model. Narrow the blast radius with `types` / `locales`, or use
`GuardAction.warn` plus your own review on high-stakes flows.

## False negatives — coverage gaps

Formats outside the current catalog pass through —
e.g. SSN without dashes (`123456789`) and unicode-domain emails (the email regex is
ASCII-only for the domain part, so `user@münchen.de` is not detected). These are scope
decisions, not defects; if you need a format,
[open an issue](https://github.com/GhagSagar23/ai_guardrails/issues) (or a PR) to add it.

## Per-scanner accuracy

Measured on 2026-11-03 against the red-team corpus (61 labeled prompts, 8 categories).
All scanners set to `GuardAction.block` to measure detection accuracy.

**Reproduce:** `dart run benchmark/accuracy.dart`

| Category | TP | FP | TN | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| benign | 0 | 0 | 15 | 0 | 1.000 | 1.000 | 1.000 |
| code_execution | 7 | 0 | 0 | 1 | 1.000 | 0.875 | 0.933 |
| invisible_text | 3 | 0 | 0 | 0 | 1.000 | 1.000 | 1.000 |
| pii | 6 | 0 | 0 | 2 | 1.000 | 0.750 | 0.857 |
| prompt_injection | 8 | 0 | 0 | 7 | 1.000 | 0.533 | 0.696 |
| repetition | 2 | 0 | 0 | 0 | 1.000 | 1.000 | 1.000 |
| secret | 3 | 0 | 0 | 2 | 1.000 | 0.600 | 0.750 |
| url | 1 | 0 | 0 | 4 | 1.000 | 0.200 | 0.333 |
| **Overall** | **30** | **0** | **15** | **16** | **1.000** | **0.652** | **0.789** |

**Key observations:**

- **Zero false positives** across all 15 benign prompts — no clean input is misclassified.
- **Prompt injection recall (53.3%)** — the heuristic rules miss subtler jailbreak
  variants (roleplay-framed, indirect instruction overrides). ML-based classifiers
  would score higher here but at inference cost.
- **URL recall (20%)** — `UrlFormatValidator` is designed for output-stage URL
  validation, not input-stage malicious URL detection. 4 of 5 URL test cases are
  input-stage (phishing TLDs, shorteners, dangerous schemes) and fall outside its scope.
- **Secret recall (60%)** — the OpenAI key and generic password patterns in the corpus
  are not covered by the current rule set (AWS, GitHub, private key blocks are).
- **PII recall (75%)** — address and name-only patterns lack regex coverage; email,
  SSN, phone, credit card, Aadhaar, and PAN are detected.

### Scanner finding breakdown

| Scanner | Cases flagged | Finding types |
| --- | ---: | --- |
| prompt_injection | 9 | instruction_override (4), system_prompt_exfiltration (1), behavior_change (2), roleplay_jailbreak (4) |
| pii | 7 | email (2), ssn (2), phone (4), credit_card (1), passport (1), ip (1), aadhaar (1), pan (1) |
| secret | 3 | aws_access_key (1), aws_secret (1), github_token (1), private_key_block (1) |
| code_exec | 7 | shell (3), injection (3), sql (2) |
| invisible_text | 3 | zero_width (6), bidi (2), soft_hyphen (5) |
| repetition | 2 | ngram (6) |

### Corpus limitations

- 61 prompts — small corpus, sufficient for regression but not statistically robust.
- No Hindi/Hinglish adversarial prompts.
- No "harmless lookalike" inputs that stress false positive resilience
  (e.g. SSN-shaped order numbers, Luhn-valid non-card sequences).
- No multi-turn / context-dependent attack chains.
- Both are open contribution targets.

## Comparison with alternatives

### Server-side moderation APIs

OpenAI Moderation, Google Cloud Natural Language, AWS Comprehend: ML-based
classification with higher recall on ambiguous inputs. Tradeoffs:

- Network roundtrip per call (50–300ms typical).
- User data leaves the device — privacy/compliance implications.
- Per-call cost ($0.001–0.01/request at scale).
- Requires connectivity.

ai_guardrails runs entirely on-device with zero network dependency, zero per-call cost,
and sub-millisecond latency. It is not a replacement for server-side moderation on
regulated data — it is a client-side pre-filter that catches the obvious cases before
they reach the network.

### Python guardrails frameworks

Guardrails AI, NeMo Guardrails, LLM Guard: mature Python ecosystems with ML-backed
detection, LLM-in-the-loop validation, and rich policy engines. Tradeoffs:

- Python-only — not available in Dart/Flutter without a backend service.
- Heavy runtime dependencies (PyTorch, transformers, sentence-transformers).
- Designed for server-side pipelines, not mobile/edge deployment.

ai_guardrails is the only pure-Dart on-device option. If your stack is Flutter or
Dart-server, the alternative is running a Python service and calling it over HTTP —
which reintroduces the latency, cost, and privacy tradeoffs above.

### Manual regex

What most Flutter developers do today: ad-hoc `RegExp` checks per field. ai_guardrails
bundles 11 PII patterns, 8 secret detection rules, prompt injection heuristics,
invisible text stripping, code execution blocking, output schema validation, and
repetition detection in a tested, maintained package. The value is not that any single
regex is hard to write — it's that the collection is pre-built, tested against a labeled
corpus, and maintained across versions.

### Tradeoff acknowledgement

ai_guardrails uses regex/heuristic detection, not ML-based classification. This means:

- **Higher false negative rate** on ambiguous or novel attacks — the prompt injection
  scanner scores 53% recall vs. ML classifiers that typically reach 85–95%.
- **Higher false positive rate** on coincidental pattern matches — SSN-shaped numbers,
  Luhn-valid non-card sequences (see [False positives](#false-positives--ambiguity-no-regex-can-resolve) above).
- **Zero inference cost**, deterministic output, no model dependency, no connectivity
  requirement, sub-millisecond latency.

The right deployment is as a fast first-pass filter — catch the obvious, let the
expensive ML check handle the rest.

## Bottom line

Treat `ai_guardrails` as a fast **first line of defense**, not a compliance guarantee —
layer server-side checks for regulated data.
