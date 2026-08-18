# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in `ai_guardrails`, please report it
responsibly via [GitHub Security Advisories](https://github.com/GhagSagar23/ai_guardrails/security/advisories/new).

Do **not** open a public issue for security vulnerabilities.

You should receive an acknowledgement within 48 hours. A fix or mitigation will
be published as a patch release as soon as practical.

## Scope

`ai_guardrails` is a pure-Dart library with zero runtime dependencies, zero
network calls, and zero telemetry. The attack surface is limited to:

- **ReDoS** in scanner regex patterns (mitigated by bounded quantifiers; see
  [`PERFORMANCE-AUDIT.md`](PERFORMANCE-AUDIT.md))
- **Bypass** of heuristic scanners via novel input formats
- **Information leakage** through `Finding.match` or `ScanResult.redactionMap`
  if exposed to untrusted consumers

## Supported versions

| Version | Supported |
| ------- | --------- |
| 0.4.x   | Yes       |
| < 0.4   | No        |
