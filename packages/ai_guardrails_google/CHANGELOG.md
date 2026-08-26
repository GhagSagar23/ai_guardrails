# Changelog

## 0.1.0

- `GuardedGenerativeModel` — wraps `GenerativeModel` with `AiGuard`
  input/output scanning.
- `generateContent()` — sync guarded calls with PII redaction/rehydration.
- `generateContentStream()` — streaming with boundary-based output scanning.
- `countTokens()` — pass-through without scanning.
- `OnBlock` enum — throw (`throwException`, default) or return
  (`returnResult`) on scanner block.
- `GuardedResponse` / `GuardedChunk` / `GuardBlockedException` result types.
