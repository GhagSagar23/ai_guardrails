/// Shelf middleware and standalone HTTP server for ai_guardrails.
///
/// Exposes [AiGuard] as REST endpoints — scan input/output, OpenAI-compatible
/// proxy, or embed as middleware in your own shelf server.
library;

export 'src/guard_handler.dart';
export 'src/guard_middleware.dart';
export 'src/policy_loader.dart';
