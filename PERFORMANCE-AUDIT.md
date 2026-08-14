# Performance & ReDoS Audit

An honest, per-scanner review of regex safety (catastrophic backtracking),
allocation behaviour, and algorithmic complexity. This is an audit, not
marketing — where something is only *bounded* rather than *provably linear*, it
says so.

## How to read the ReDoS verdicts

Dart's `RegExp` is a **backtracking engine** (irregexp — the same lineage as
V8's; on the web, dart2js hands off to the host JS engine, also backtracking).
It is **not** RE2, so there is no built-in linear-time guarantee: catastrophic
(exponential) backtracking is possible *in principle*. It requires a specific
shape — a **quantifier applied to a group that itself contains a quantifier over
an overlapping character set** (`(a+)+`, `(a*)*`, `(.*)*`, `(a|a)*`). The audit's
job is to confirm that the built-in patterns avoid that shape.

Milder **polynomial** (O(n²)) backtracking can arise from two *adjacent*
ambiguous quantifiers over overlapping classes (`X+ . X+`). Where that exists
but is gated behind a required anchor (a literal that must appear first), it is
called out but rated safe, because the number of viable start positions is
small in practice.

Verdicts: **safe** (no exponential shape; worst case linear or bounded
polynomial gated by an anchor) or **needs-attention**.

---

## PiiScanner — `lib/src/scanners/pii_scanner.dart` + `lib/src/data/pii_patterns.dart`

Runs each active `PiiPattern.regex` over the text with `allMatches`, drops
credit-card matches that fail Luhn, then (for redact/hash) rebuilds the string.

**Per-pattern ReDoS review** (11 patterns):

| Pattern | Shape | Verdict |
| --- | --- | --- |
| `email` `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}` | Two `+` runs split by a required literal `@` (not in the left class → left side unambiguous). Right side `[A-Za-z0-9.-]+\.[A-Za-z]{2,}` is a single ambiguous `X+ \. Y+` (dot/letters overlap). No nested quantifier. | **safe** — worst case is *polynomial*, not exponential, and only after an `@` anchor. |
| `phone` (US/EU/India) | Only bounded quantifiers (`{3}`, `{2,4}`, `{9}`) and optional single separators. | **safe** — linear. |
| `ssn` `\d{3}-\d{2}-\d{4}` | Bounded literals. | **safe**. |
| `credit_card` `\b(?:\d{13,19}\|\d{4}(?:[ -]?\d{4}){2,4})\b` | Alternation; inner group repetition is **bounded** `{2,4}` over bounded `\d{4}`; branch 1 bounded `{13,19}`. No unbounded nesting. | **safe** — bounded backtracking even on a long digit run. |
| `iban` `[A-Z]{2}\d{2}[A-Z0-9]{10,30}` | Bounded `{10,30}`. | **safe**. |
| `ip` `(?:\d{1,3}\.){3}\d{1,3}` | Fixed `{3}` repeat, inner bounded. | **safe**. |
| `aadhaar` / `pan` / `passport` | Bounded literals. | **safe**. |

**Verdict: safe.** No pattern contains a quantifier-over-quantifier with
overlapping classes, so no exponential blow-up. The file's header comment
("linear, ReDoS-safe") is essentially correct; the one nuance is `email`, whose
right half is *bounded polynomial*, gated behind a required `@`.

**Allocation / memory:** the real cost centre.
- Detection allocates one `Finding` per match and a `List<Finding>`.
- **Redaction (`_transform`) runs `replaceAllMapped` once per active pattern**
  — up to **11 full-length string rebuilds**, each producing a fresh string.
  This is why `PiiScanner(redact)` is the slowest scanner in the benchmark
  (~400 us, ~2.8 MB/s). Cost is **O(patterns × n)** in both time and transient
  allocation.
- Luhn strips separators with `replaceAll(RegExp(r'[^0-9]'), '')`, allocating a
  small string per candidate. Negligible.

**Complexity:** detection **O(patterns × n)** regex scan; Luhn **O(d)** over the
digits of a candidate; redaction **O(patterns × n)**.

**Fix (optional):** collect all match spans in one pass, sort/merge, and rebuild
the string **once** instead of once per pattern. Cuts the dominant cost of PII
redaction from `O(patterns × n)` string rebuilds to `O(n)`.

---

## SecretScanner — `lib/src/scanners/secret_scanner.dart`

Eight `_SecretRule`s; each `allMatches` pass adds findings, then redact/hash
rebuilds per rule.

**Per-rule ReDoS review:**

| Rule | Shape | Verdict |
| --- | --- | --- |
| `aws_access_key` `AKIA[A-Z0-9]{16}` | Bounded. | **safe**. |
| `aws_secret` `aws[\s\S]{0,40}?[A-Za-z0-9/+]{40}` (ci) | **Bounded** lazy gap `{0,40}` + fixed `{40}`; no nesting. Per `aws` occurrence ≤ ~41×40 attempts. | **safe** — heaviest constant factor of the set, but bounded and gated by the literal `aws`. |
| `gcp_api_key` `AIza[A-Za-z0-9_-]{35}` | Bounded. | **safe**. |
| `github_token` `gh[pousr]_[A-Za-z0-9]{36,}` | Single unbounded `{36,}`, nothing follows → greedy consume, no backtracking. | **safe** — linear. |
| `openai_key` `sk-[A-Za-z0-9]{20,}` | Single unbounded, nothing follows. | **safe** — linear. |
| `slack_token` `xox[baprs]-[A-Za-z0-9-]{10,}` | Single unbounded, nothing follows. | **safe** — linear. |
| `jwt` `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | Three `+` runs, but the separator `.` is **not** in the class → segmentation is unambiguous. Gated by literal `eyJ`. | **safe** — linear despite the scary look. |
| `private_key_block` `-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END ...` | Lazy `[\s\S]*?` bounded by a required literal terminator; no nested quantifier. | **safe** — but see note. |

**Verdict: safe.** No exponential shape. One residual: `private_key_block` can
degrade to **O(n²)** if the input contains **many `-----BEGIN … PRIVATE KEY-----`
markers with no matching `END`** — each unterminated BEGIN drives the lazy body
to EOF. Requires crafted input; low severity.

**Allocation / memory:** `Finding.match` is deliberately **null** for secrets
(never echo a secret). Redact/hash runs `replaceAllMapped` **once per rule**
(up to 8 rebuilds) — same `O(rules × n)` rebuild pattern as PII, but with far
fewer matches in practice so it is cheap in the benchmark (~8 us detect-only).

**Complexity:** detection **O(rules × n)**; findings sorted **O(k log k)** by
start; redaction **O(rules × n)**.

---

## PromptInjectionScanner — `lib/src/scanners/prompt_injection_scanner.dart`

Runs the `kInjectionSignals` table (5 groups, ~15 regexes total) over the text,
sums fired weights, clamps to 1.0.

**ReDoS review:** the "gap" patterns use **bounded lazy gaps** — `[^\n]{0,40}?`,
`[^\n]{0,30}?`, `(system\s+)?` — anchored between required word alternations.
The only unbounded quantifiers are simple single runs (`\s+`, `#{2,}`) with no
overlapping neighbour. No quantifier-over-quantifier anywhere.

**Verdict: safe** — linear. The bounded `[^\n]{0,N}?` gap is exactly the
right ReDoS-avoidance idiom; keep new signals to the same shape.

**Allocation / memory:** one `Finding` per raw match; redact/hash re-run every
fired pattern with `replaceAll`/`replaceAllMapped` (rebuild per fired pattern).
Detection allocates a small `matched` list. All proportional to matches.

**Complexity:** **O(patterns × n)** with `patterns` a small constant (~15).
~98 us/scan in the benchmark reflects running 15 regexes over each ~1.25 KB
string.

---

## BannedTopicScanner — `lib/src/scanners/banned_topic_scanner.dart`

Builds one `\b<RegExp.escape(topic)>\b` per topic.

**ReDoS review:** topics are **escaped** (`RegExp.escape`), so a caller cannot
inject quantifiers; each pattern is a literal bracketed by `\b`. No quantifiers
at all.

**Verdict: safe** — linear, **O(topics × n)**. (Correctness caveat already noted
in-source: `\b` won't anchor topics that begin/end with punctuation like `c++`;
that is a matching-accuracy issue, not a performance one.)

**Allocation / memory:** one `Finding` per match; redact/hash rebuild once per
topic. Cheap (fastest scanners in the benchmark, ~2.8 us).

---

## BannedPatternScanner — `lib/src/scanners/banned_pattern_scanner.dart`

Runs a **caller-supplied** list of `Pattern`s (literal `String` or `RegExp`).

**ReDoS review:** the scanner adds **no quantifiers of its own** — but it will
execute whatever regex the caller passes. If a caller supplies a pathological
pattern (`(a+)+`, `(.*)*`, …), the catastrophic backtracking happens here.

**Verdict: safe for built-in/first-party usage; needs-attention for untrusted
or careless patterns.** This is the one scanner whose ReDoS surface is
**delegated to the caller**. Recommended guidance:
- keep custom patterns **flat** (no nested unbounded quantifiers);
- for patterns from untrusted config, run this scanner inside `Isolate.run` so a
  runaway match can't wedge the UI isolate;
- prefer literal `String` patterns where precision allows (no backtracking at
  all).

**Complexity:** **O(patterns × n)** for flat patterns; unbounded if a caller
supplies a pathological regex.

---

## TokenLimitScanner — `lib/src/scanners/token_limit_scanner.dart`

Counts tokens with `RegExp(r'\w+|[^\w\s]+').allMatches(text).length`.

**ReDoS review:** an alternation of two `+` runs over **disjoint** classes
(`\w` vs non-word-non-space). Disjoint → unambiguous → no backtracking.

**Verdict: safe** — linear **O(n)**.

**Allocation / memory:** `allMatches(...).length` iterates a lazy `Iterable`
(no `List` is built), but each token materialises a transient `Match` object →
GC pressure proportional to the token count on very large inputs. Minor; a
manual character scan would avoid the `Match` allocation entirely if this ever
matters.

**Complexity:** **O(n)** scan; **O(tokens)** transient allocation.

---

## InvisibleTextScanner — `lib/src/scanners/invisible_text_scanner.dart`

No regex. Iterates `text.runes` and tests each code point against 4 category
predicates.

**ReDoS review:** not applicable — no regex.

**Verdict: safe** — **O(n × 4)** = O(n). Correctly rune-aware, so astral
tag-block characters (surrogate pairs) are handled and offsets are correct
UTF-16 code-unit indices.

**Allocation / memory:** one `Finding` per invisible char (proportional to
invisibles, usually tiny). Redact/hash rebuild via a single `StringBuffer`
pass — **O(n)**, one new string, no per-pattern re-rebuild. The most
allocation-efficient of the transforming scanners.

**Complexity:** **O(n)** detect; **O(n)** rewrite.

---

## SchemaValidator — `lib/src/scanners/schema_validator.dart`

`jsonDecode` the text, then check top-level `type`, `required` keys, and
per-property `type`.

**ReDoS review:** not applicable — no regex; parsing is `dart:convert`.

**Verdict: safe** — no backtracking surface.

**Allocation / memory:** `jsonDecode` builds the **entire decoded object graph**
in memory — this is the dominant allocation and scales with input size and
nesting. The subsequent checks iterate schema-defined keys (fixed by the
schema, not attacker-controlled).

**Complexity:** **O(n)** parse + **O(required + properties)** checks.

---

## Recommended maximum input size for the UI isolate

Planning number: use the **slowest** path, `PiiScanner(redact)` at **~2.8
MB/s** (it also dominates the full pipeline). Budgets:

| Latency budget | ~Max input at 2.8 MB/s |
| --- | ---: |
| 1 frame @ 60 fps (~16 ms) | **~45 KB** |
| "no visible jank on a tap" (~50 ms) | **~140 KB** |

**Guideline:** scanning inputs up to **~50 KB** on the UI isolate is safe
(single-digit to low-tens of milliseconds). Typical chat prompts are a few KB or
less and cost **well under 1 ms** — guard them inline without a second thought.

**Offload threshold:** for inputs beyond **~100 KB** — pasted documents,
uploaded files, RAG chunks — move the scan off the UI isolate:

```dart
final results = await Isolate.run(() => guard.scanInput(text));
```

Scanners are pure and synchronous, so they move to a worker isolate cleanly (no
shared mutable state to marshal). Cost is linear in input size, so a 1 MB input
is ~350 ms of PII-redact work — fine on a worker, a visible stall on the UI
isolate.

---

## Residual risks / future hardening

1. **Caller-supplied regexes (`BannedPatternScanner`) are an unguarded ReDoS
   surface.** Document the "flat patterns only" rule; for untrusted config, run
   the scanner in an isolate or add a match wall-clock guard. Consider a
   literal-only mode.
2. **Findings lists are unbounded relative to input.** A crafted input with
   thousands of matches inflates memory and the `reason` string. Cap findings
   per scanner (first N + a count) if inputs can be adversarial in size.
3. **Multi-pass redaction rebuilds the whole string once per pattern/rule.**
   `PiiScanner` now resolves overlapping findings once and rebuilds in a single
   offset-based splice (O(n), no second regex pass). Other scanners that redact
   (e.g. `SecretScanner` with `GuardAction.redact`) still re-run each pattern —
   O(patterns × n) transient allocation. Give them the same span-merge rebuild
   for a large win on big inputs.
4. **Pipeline redaction compounds.** Each redacting scanner rebuilds the full
   string and feeds it forward, so the chain is O(scanners × n) allocation.
   Fine at chat sizes; grows with large inputs — another reason to offload
   those.
5. **The ReDoS guarantee rests on an invariant, not the engine.** Dart's regex
   is a backtracking engine; safety here comes from every built-in pattern
   avoiding nested unbounded quantifiers over overlapping classes. Protect the
   invariant with a fuzz test (pathological inputs + a per-scan wall-clock
   assertion) so a future pattern can't silently reintroduce the shape.
6. **`private_key_block` can go O(n²)** on inputs with many unterminated
   `-----BEGIN … PRIVATE KEY-----` markers. Low severity; bound the END search
   window if this ever surfaces.
7. **`TokenLimitScanner` allocates a transient `Match` per token.** Replace the
   `allMatches().length` count with a manual scan if very large inputs need it.
8. **No library-level input-size guard.** Nothing stops a caller handing a 10 MB
   string to the UI isolate. Consider an optional `maxInputChars` fast-fail, or
   rely on the offload guidance above.
9. **`PiiScanner` overlap resolution is leftmost-longest, not span-union.** A
   *partial* overlap (span B starts inside kept span A but extends past A's end)
   drops B, leaving B's tail un-redacted. With the current `kPiiPatterns` two
   matches are always disjoint or fully nested, never partial, so this is
   unreachable today — but a future partially-overlapping pattern would need a
   union merge (over-redact) instead of drop to stay leak-safe.
