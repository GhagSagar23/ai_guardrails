import 'ai_guard.dart';

/// Stateful multi-turn wrapper around [AiGuard].
///
/// Tracks turn count across a conversation. The wrapped [AiGuard] and its
/// scanners remain stateless — session state lives here.
class GuardSession {
  final AiGuard guard;

  int _turnCount = 0;

  GuardSession({required this.guard});

  /// Number of completed `run()` calls in this session.
  int get turnCount => _turnCount;

  /// Delegates to [guard.run] and increments the turn counter.
  Future<GuardOutcome> run({
    required String input,
    required Future<String> Function(String sanitizedInput) llmCall,
  }) async {
    final outcome = await guard.run(input: input, llmCall: llmCall);
    _turnCount++;
    return outcome;
  }

  /// Resets session state for reuse.
  void reset() {
    _turnCount = 0;
  }
}
