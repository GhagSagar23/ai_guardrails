# PII round-trip

Back to [README](../README.md).

---

When `PiiScanner` redacts input, the LLM sees placeholders like `[EMAIL_1]`.
If the model echoes those placeholders in its response, `AiGuard` automatically
**rehydrates** them — `outcome.output` comes back with the original PII restored:

```dart
final guard = AiGuard(
  inputScanners: [PiiScanner(action: GuardAction.redact)],
);

final outcome = await guard.run(
  input: 'Email alice@work.com and bob@work.com about the release.',
  llmCall: (sanitized) => myLlm.complete(sanitized),
  // sanitized = "Email [EMAIL_1] and [EMAIL_2] about the release."
);

print(outcome.output);    // "I've emailed alice@work.com and bob@work.com."
print(outcome.rawOutput); // "I've emailed [EMAIL_1] and [EMAIL_2]."
print(outcome.piiMap);    // {[EMAIL_1]: alice@work.com, [EMAIL_2]: bob@work.com}
```

Each PII type gets an independent counter (`[EMAIL_1]`, `[SSN_1]`), so multiple
occurrences of the same type are distinguishable. Hash-mode placeholders
(`[EMAIL:a1b2c3]`) are already unique and work the same way.

## Caveats

Rehydration is **always-on** — there is no opt-out flag today. It runs **after** output
scanners, so output scanners see placeholders (safe), but the final `outcome.output`
contains restored PII. If your output leaves the device (logging, analytics, downstream
API), handle the restored values accordingly.

## Fail-closed behaviour

`AiGuard` is **fail-closed by default** (`failClosed: true`): if a scanner throws, the
request is blocked rather than silently passed. Set `failClosed: false` to skip a
throwing scanner instead.
