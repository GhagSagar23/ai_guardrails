<p align="center">
  <img src="https://raw.githubusercontent.com/GhagSagar23/ai_guardrails/master/icon/ai_guardrails.svg" width="120" alt="ai_guardrails logo" />
</p>

<h1 align="center">ai_guardrails_anthropic</h1>

<p align="center">
  <strong>Drop-in safety wrapper for <code>anthropic_sdk_dart</code></strong>
</p>

<p align="center">
  <a href="https://pub.dev/packages/ai_guardrails_anthropic"><img src="https://img.shields.io/pub/v/ai_guardrails_anthropic.svg?label=pub&color=0175C2" alt="pub version" /></a>
  <a href="https://pub.dev/packages/ai_guardrails"><img src="https://img.shields.io/pub/v/ai_guardrails.svg?label=ai_guardrails&color=0175C2" alt="ai_guardrails version" /></a>
  <a href="https://github.com/GhagSagar23/ai_guardrails/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/GhagSagar23/ai_guardrails/ci.yml?branch=master&label=CI" alt="CI status" /></a>
  <a href="https://github.com/GhagSagar23/ai_guardrails/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License" /></a>
</p>

---

`ai_guardrails_anthropic` wraps Anthropic's `AnthropicClient` with automatic
[`ai_guardrails`](https://pub.dev/packages/ai_guardrails) input/output
scanning. PII is redacted before the prompt leaves the device and rehydrated
in the response; prompt injection, secrets, and other violations are blocked
or warned — all without changing your Anthropic calling code.

## Install

```bash
dart pub add ai_guardrails_anthropic
```

This pulls in `ai_guardrails` and `anthropic_sdk_dart` transitively.

## Quick start

```dart
import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_anthropic/ai_guardrails_anthropic.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

final guarded = GuardedAnthropicClient(
  client: AnthropicClient(apiKey: apiKey),
  guard: AiGuard(
    inputScanners: [
      PiiScanner(action: GuardAction.redact),
      PromptInjectionScanner(),
      SecretScanner(),
    ],
    outputScanners: [SecretScanner()],
  ),
);

final result = await guarded.createMessage(
  request: CreateMessageRequest(
    model: const Model.modelId('claude-sonnet-4-20250514'),
    maxTokens: 1024,
    messages: [
      Message(
        role: MessageRole.user,
        content: MessageContent.text(
          'My email is alice@example.com. Summarise the weather.',
        ),
      ),
    ],
  ),
);

print(result.text);           // PII auto-rehydrated
print(result.redactionMap);   // {[EMAIL_1]: alice@example.com}
print(result.allFindings);    // every scanner finding
```

## Streaming

```dart
await for (final chunk in guarded.createMessageStream(
  request: request, // a CreateMessageRequest
  boundary: '\n', // scan at newline boundaries (default)
)) {
  if (chunk.blocked) {
    print('Blocked: ${chunk.blockReason}');
    break;
  }
  stdout.write(chunk.text);
}
```

Output chunks are buffered and scanned at `boundary` splits. On block the
stream terminates — either by throwing `GuardBlockedException` (default) or
yielding a final blocked `GuardedChunk` when `onBlock: OnBlock.returnResult`.

## Block behaviour

| `OnBlock` | On block |
| --- | --- |
| `throwException` (default) | Throws `GuardBlockedException` |
| `returnResult` | Returns `GuardedResponse` / `GuardedChunk` with `blocked: true` |

```dart
final guarded = GuardedAnthropicClient(
  client: client,
  guard: guard,
  onBlock: OnBlock.returnResult, // don't throw, return blocked result
);
```

## PII round-trip

When `PiiScanner` redacts input, the model sees placeholders (`[EMAIL_1]`).
If the model echoes them, `GuardedAnthropicClient` rehydrates the original
values in both sync and streaming responses — your app gets the real data
back without ever sending it to the API.

## API

### `GuardedAnthropicClient`

| Method | Returns | Notes |
| --- | --- | --- |
| `createMessage(request:)` | `Future<GuardedResponse>` | Full input scan → API call → output scan |
| `createMessageStream(request:, {boundary})` | `Stream<GuardedChunk>` | Same, streaming with per-segment output scan |

### `GuardedResponse`

| Property | Type | Notes |
| --- | --- | --- |
| `blocked` | `bool` | Whether a scanner blocked |
| `blockedStage` | `ScanStage?` | `.input` or `.output` |
| `blockReason` | `String?` | Human-readable reason |
| `text` | `String?` | Rehydrated response text |
| `message` | `Message?` | Raw Anthropic response (`null` on input block) |
| `allFindings` | `List<Finding>` | Combined input + output findings |
| `redactionMap` | `Map<String, String>` | Placeholder → original PII |

### `GuardedChunk`

| Property | Type | Notes |
| --- | --- | --- |
| `text` | `String` | Segment text (PII rehydrated) |
| `blocked` | `bool` | Whether this segment was blocked |
| `blockReason` | `String?` | Reason if blocked |
| `findings` | `List<Finding>` | Findings for this segment |

## Scanners

Any scanner from [`ai_guardrails`](https://pub.dev/packages/ai_guardrails)
works — `PiiScanner`, `SecretScanner`, `PromptInjectionScanner`,
`GroundingScanner`, `SchemaValidator`, custom `Scanner`/`AsyncScanner`, etc.
See the [ai_guardrails README](https://pub.dev/packages/ai_guardrails) for
the full scanner catalog.

## Example

See [`example/guarded_chat_example.dart`](example/guarded_chat_example.dart)
for a runnable demo with sync + streaming calls.

## Requirements

- Dart SDK `^3.5.0`
- `ai_guardrails: >=0.8.0 <2.0.0`
- `anthropic_sdk_dart: ^0.1.0`

## License

[Apache-2.0](https://github.com/GhagSagar23/ai_guardrails/blob/master/LICENSE) © GhagSagar23
