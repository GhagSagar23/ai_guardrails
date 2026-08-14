# Contributing to ai_guardrails

Thanks for your interest in improving `ai_guardrails`. This is a small, pure-Dart
safety library, and we keep the contribution process deliberately strict so that
every change is discussed and agreed **before** anyone writes code.

> **TL;DR:** No issue, no PR. Open an issue, get it accepted, *then* fork and send
> a Pull Request. **Unsolicited PRs without an accepted issue may be closed.**

---

## The contribution flow (read this first)

Follow these steps **in order**. Skipping a step is the fastest way to have your
work closed unmerged.

### 1. Open a GitHub issue FIRST

Before you write any code, [open an issue](https://github.com/GhagSagar23/ai_guardrails/issues/new/choose)
— a **bug** or a **feature** — describing the change you want to make.
**Do not send a PR before this.** The issue is where the change gets discussed,
scoped, and agreed.

### 2. Wait for a maintainer to accept the issue

A maintainer will **triage** your issue and, if it's a good fit, **accept** it by
applying an `accepted` / `good-to-go` label. This is your green light.
Please wait for that label before starting work — it avoids wasted effort on
changes we can't take.

### 3. Only after acceptance: FORK the repository

Once your issue is accepted, [fork the repository](https://github.com/GhagSagar23/ai_guardrails/fork)
to your own account.

### 4. Create a topic branch off `master`

In your fork, branch off `master`:

```bash
git checkout master
git pull upstream master        # keep master current
git checkout -b fix/short-description
```

### 5. Make your change, then open a PR from your fork

Implement the change **with tests**, then open a Pull Request **from your fork**
targeting the **`master`** branch of **`GhagSagar23/ai_guardrails`**.
**Link the accepted issue** in the PR description (e.g. `Closes #123`).

---

**Unsolicited PRs without an accepted issue may be closed** without review.
The issue-first flow isn't bureaucracy — it's how we make sure your time is spent
on a change we can actually merge.

---

## Local development setup

Pure Dart, no Flutter required. From the repo root:

```bash
dart pub get      # fetch dependencies
dart test         # run the test suite
dart analyze      # static analysis (must be clean)
dart format .     # format all Dart sources
```

Run all four before pushing. CI runs the same checks and will reject anything
that fails them.

## Project conventions

These are firm. PRs that break them will be sent back:

- **Pure Dart.** No Flutter, no platform channels, no `dart:io` in `lib/`.
- **No new runtime dependencies.** `ai_guardrails` ships with zero runtime deps
  and stays that way. Test-only `dev_dependencies` are fine when justified.
- **Scanners implement the `Scanner` contract** (`lib/src/scanner.dart`).
- **Scanners are synchronous and dependency-free.** No I/O, no network, no async,
  no mutable shared state — the pipeline must stay deterministic and cheap enough
  to run on the UI isolate. This is enforced by the `Scanner` contract, which is
  frozen public API.
- **Every scanner needs thorough tests** — positive matches, negatives, edge
  cases (empty string, unicode, overlapping spans), and the chosen `GuardAction`
  behaviour.
- Honour `analysis_options.yaml` (`prefer_single_quotes`, `prefer_final_locals`,
  `avoid_print`, strict casts/raw-types). `dart analyze` must be clean.

## Authoring a new scanner

1. **Implement `Scanner`** — provide `name`, `stages`, and `scan(...)` returning
   a `ScanResult`. Keep it pure and synchronous.
2. **Put it under `lib/src/scanners/`**, one scanner per file
   (e.g. `lib/src/scanners/my_scanner.dart`).
3. **Add tests** under `test/` covering matches, non-matches, and edge cases.
4. **Maintainers wire the barrel export.** Don't edit `lib/ai_guardrails.dart`
   yourself — a maintainer adds the `export` when your scanner is accepted, so
   the public surface stays curated.

A minimal skeleton:

```dart
import '../scanner.dart';

class MyScanner implements Scanner {
  @override
  String get name => 'my_scanner';

  @override
  Set<ScanStage> get stages => const {ScanStage.input};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    // ... detect, build findings, return a ScanResult ...
    return ScanResult.pass(name, text);
  }
}
```

## Commit messages

Keep them concise. One short imperative subject line that says what changed
(e.g. `add invisible-text scanner`, `fix email regex over-match`). Reference the
issue where it helps. Sacrifice grammar for brevity over padding.

## CI

Every push and PR against `master` runs:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

All three must pass. Format your code, keep analysis clean, and make sure the
full test suite is green **before** you open the PR — a red CI run blocks merge.

## Code of Conduct

By participating you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).
