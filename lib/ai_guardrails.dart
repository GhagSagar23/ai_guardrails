/// Provider-agnostic input/output safety scanners for Dart & Flutter AI apps.
///
/// Compose [Scanner]s into an [AiGuard] and wrap any LLM call — local or
/// cloud — to redact PII, block prompt injection and secret leakage, and
/// validate model output. Pure Dart, on-device, zero network.
library;

export 'src/scanner.dart';
export 'src/ai_guard.dart';
export 'src/data/pii_patterns.dart';
export 'src/scanners/pii_scanner.dart';
export 'src/scanners/secret_scanner.dart';
export 'src/scanners/prompt_injection_scanner.dart';
export 'src/scanners/banned_topic_scanner.dart';
export 'src/scanners/banned_pattern_scanner.dart';
export 'src/scanners/token_limit_scanner.dart';
export 'src/scanners/invisible_text_scanner.dart';
export 'src/scanners/schema_validator.dart';
