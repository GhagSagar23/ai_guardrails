/// Provider-agnostic input/output safety scanners for Dart & Flutter AI apps.
///
/// Compose [Scanner]s into an [AiGuard] and wrap any LLM call — local or
/// cloud — to redact PII, block prompt injection and secret leakage, and
/// validate model output. Pure Dart, on-device, zero network.
library;

export 'src/scanner.dart';
export 'src/ai_guard.dart';
export 'src/guard_log.dart';
export 'src/guard_metrics.dart';
export 'src/data/pii_patterns.dart';
export 'src/scanners/pii_scanner.dart';
export 'src/scanners/secret_scanner.dart';
export 'src/scanners/prompt_injection_scanner.dart';
export 'src/scanners/banned_topic_scanner.dart';
export 'src/scanners/banned_pattern_scanner.dart';
export 'src/scanners/token_limit_scanner.dart';
export 'src/scanners/invisible_text_scanner.dart';
export 'src/scanners/repetition_scanner.dart';
export 'src/scanners/url_scanner.dart';
export 'src/scanners/language_scanner.dart';
export 'src/scanners/code_execution_scanner.dart';
export 'src/scanners/grounding_scanner.dart';
export 'src/scanners/schema_validator.dart';
export 'src/scanners/tool_call_scanner.dart';
export 'src/scanners/padding_attack_scanner.dart';
export 'src/scanners/hallucination_scanner.dart';
export 'src/scanners/fact_check_scanner.dart';
export 'src/scanners/topic_safety_scanner.dart';
export 'src/guard_session.dart';
export 'src/streaming_ai_guard.dart';
export 'src/scanner_registry.dart';
export 'src/policy.dart';
export 'src/policy_profile.dart';
export 'src/guard_benchmark.dart';
export 'src/on_fail_action.dart';
export 'src/guarded_llm_call.dart';
export 'src/scanners/tool_output_scanner.dart';
