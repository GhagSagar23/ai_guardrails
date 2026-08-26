// ignore_for_file: avoid_print
import 'dart:io';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_google/ai_guardrails_google.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Guarded Gemini chat with PII redaction and prompt injection blocking.
///
/// Run: `GOOGLE_API_KEY=<key> dart run example/guarded_chat_example.dart`
void main() async {
  final apiKey = Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Set GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  final guarded = GuardedGenerativeModel(
    model: GenerativeModel(model: 'gemini-2.0-flash', apiKey: apiKey),
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

  // --- Sync example ---
  print('=== Sync (generateContent) ===\n');

  final syncResult = await guarded.generateContent(
    [Content.text('My email is alice@example.com. Summarise the weather.')],
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
  print('\n=== Streaming (generateContentStream) ===\n');

  stdout.write('Response: ');
  await for (final chunk in guarded.generateContentStream(
    [Content.text('Tell me a short joke.')],
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
