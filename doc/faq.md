# FAQ

Back to [README](../README.md).

---

**Q: I'm getting false positives on order IDs / tracking numbers.**
Use `types` to limit `PiiScanner` to only the PII types you care about, or switch to
`GuardAction.warn` and review findings before acting on them.

**Q: Can I use this with streaming APIs like Gemini or OpenAI?**
Yes. `StreamingAiGuard` wraps any `Stream<String>` and scans per-segment. See
[streaming.md](streaming.md).

**Q: Does this package phone home or collect telemetry?**
No. Built-in heuristic scanners make zero network calls. LLM-assisted scanners
(`HallucinationScanner`, `FactCheckScanner`, `TopicSafetyScanner`,
`EmbeddingGroundingScanner`) use callbacks you provide — those may call cloud services,
but the package itself never phones home. Zero telemetry, zero runtime dependencies.

**Q: Why are built-in scanners synchronous?**
So they can run on the UI isolate without blocking frames, compose deterministically,
and stay testable without async machinery. For heavier work like on-device ML inference,
implement `AsyncScanner` instead — `AiGuard` awaits both types in the same pipeline.
