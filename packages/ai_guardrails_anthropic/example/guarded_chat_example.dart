// ignore_for_file: avoid_print
import 'dart:io';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_anthropic/ai_guardrails_anthropic.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' hide Message;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a show Message;

/// Guarded Claude chat with PII redaction and prompt injection blocking.
///
/// Run: `ANTHROPIC_API_KEY=<key> dart run example/guarded_chat_example.dart`
void main() async {
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Set ANTHROPIC_API_KEY environment variable.');
    exit(1);
  }

  final guarded = GuardedAnthropicClient(
    client: AnthropicClient(apiKey: apiKey),
    guard: AiGuard(
      inputScanners: [
        PiiScanner(action: GuardAction.redact),
        PromptInjectionScanner(),
        SecretScanner(),
      ],
      outputScanners: [
        SecretScanner(),
      ],
    ),
    onBlock: OnBlock.returnResult,
  );

  CreateMessageRequest request(String prompt) => CreateMessageRequest(
        model: const Model.modelId('claude-sonnet-4-20250514'),
        maxTokens: 1024,
        messages: [
          a.Message(
              role: MessageRole.user, content: MessageContent.text(prompt)),
        ],
      );

  // --- Sync example ---
  print('=== Sync (createMessage) ===\n');

  final syncResult = await guarded.createMessage(
    request: request('My email is alice@example.com. Summarise the weather.'),
  );

  if (syncResult.blocked) {
    print('Blocked at ${syncResult.blockedStage}: ${syncResult.blockReason}');
  } else {
    print('Response: ${syncResult.text}');
    if (syncResult.redactionMap.isNotEmpty) {
      print('PII redacted: ${syncResult.redactionMap}');
    }
    if (syncResult.allFindings.isNotEmpty) {
      print(
          'Findings: ${syncResult.allFindings.map((f) => f.type).join(', ')}');
    }
  }

  // --- Streaming example ---
  print('\n=== Streaming (createMessageStream) ===\n');

  stdout.write('Response: ');
  await for (final chunk in guarded.createMessageStream(
    request: request('Tell me a short joke.'),
    boundary: '\n',
  )) {
    if (chunk.blocked) {
      print('\nBlocked: ${chunk.blockReason}');
      break;
    }
    stdout.write(chunk.text);
  }
  print('');
}
