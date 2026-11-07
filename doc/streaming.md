# Streaming

Back to [README](../README.md).

---

`StreamingAiGuard` wraps streaming LLM responses — it buffers chunks, scans at
configurable boundaries, and yields `GuardedChunk`s. If a scanner blocks, the stream
terminates immediately.

```dart
final guard = StreamingAiGuard(
  inputScanners: [PiiScanner(action: GuardAction.redact)],
  outputScanners: [UrlScanner()],
  boundary: '\n', // scan per line (default)
);

await for (final chunk in guard.run(
  input: 'Email alice@work.com about the release.',
  llmStream: (sanitized) => myLlm.streamCompletion(sanitized),
)) {
  if (chunk.blocked) {
    print('Blocked: ${chunk.blockReason}');
    break;
  }
  stdout.write(chunk.text); // PII auto-rehydrated per chunk
}
```

## Limitations

Scanners see each segment independently — **cross-segment patterns are not detected**.
Use `AiGuard` for full-output scanning (e.g. `SchemaValidator`) after the stream
completes when you need whole-response coverage.

> **Note:** When a chunk is blocked, `chunk.text` still contains the **original flagged
> segment**. Always check `chunk.blocked` before consuming `chunk.text` — do not display
> or forward blocked chunk text to end users.
