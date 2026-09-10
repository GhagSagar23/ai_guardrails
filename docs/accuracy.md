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

## Red-team corpus & accuracy testing

The red-team test corpus (62 prompts, shipped in 0.9.0) and `GuardBenchmark` harness
provide precision/recall/F1 measurement, but per-scanner accuracy numbers and false
positive rates are **not yet published** in this documentation. The corpus does not yet
include Hindi/Hinglish adversarial prompts or "harmless lookalike" inputs that test
false positive resilience — both are open contribution targets.

## Bottom line

Treat `ai_guardrails` as a fast **first line of defense**, not a compliance guarantee —
layer server-side checks for regulated data.
