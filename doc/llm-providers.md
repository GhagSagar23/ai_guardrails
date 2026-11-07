# LLM provider integration

Back to [README](../README.md).

---

`ai_guardrails` is provider-agnostic — it wraps any `Future<String> Function(String)`
as your LLM call. Here's how it looks with `google_generative_ai`:

```dart
import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

final model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: apiKey);

final guard = AiGuard(
  inputScanners: [
    PiiScanner(action: GuardAction.redact),
    SecretScanner(),
    PromptInjectionScanner(),
  ],
  outputScanners: [
    GroundingScanner(context: mySourceDocs),
    RepetitionScanner(),
  ],
);

final outcome = await guard.run(
  input: userMessage,
  llmCall: (sanitized) async {
    final response = await model.generateContent([Content.text(sanitized)]);
    return response.text ?? '';
  },
);
```

The same pattern works with any Dart LLM client: `anthropic_sdk_dart`,
`langchain_dart`, `ollama_dart`, or a plain `http.Client` calling your own gateway.

## Using scanInput / scanOutput standalone

Need just one side? Use `guard.scanInput(text)` or `guard.scanOutput(text)` for the
per-scanner `List<ScanResult>` without calling an LLM.
