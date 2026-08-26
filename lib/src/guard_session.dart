import 'ai_guard.dart';

/// Stateful multi-turn wrapper around [AiGuard].
///
/// Tracks turn count and accumulates findings across a conversation. The
/// wrapped [AiGuard] and its scanners remain stateless — session state
/// lives here.
class GuardSession {
  final AiGuard guard;

  int _turnCount = 0;
  final _turnHistory = <GuardOutcome>[];
  final _findingCounts = <String, int>{};
  final _scannerCounts = <String, int>{};

  GuardSession({required this.guard});

  /// Number of completed `run()` calls in this session.
  int get turnCount => _turnCount;

  /// Ordered outcomes from every `run()` call in this session.
  List<GuardOutcome> get turnHistory => List.unmodifiable(_turnHistory);

  /// Most recent outcome, or `null` before the first `run()`.
  GuardOutcome? get lastOutcome =>
      _turnHistory.isEmpty ? null : _turnHistory.last;

  /// Accumulated finding counts by finding type across all turns.
  Map<String, int> get findingCounts => Map.unmodifiable(_findingCounts);

  /// Accumulated finding counts by scanner name across all turns.
  Map<String, int> get scannerCounts => Map.unmodifiable(_scannerCounts);

  /// Delegates to [guard.run], accumulates findings, increments turn counter.
  Future<GuardOutcome> run({
    required String input,
    required Future<String> Function(String sanitizedInput) llmCall,
  }) async {
    final outcome = await guard.run(input: input, llmCall: llmCall);
    _turnCount++;
    _turnHistory.add(outcome);
    _accumulate(outcome);
    return outcome;
  }

  /// Resets all session state for reuse.
  void reset() {
    _turnCount = 0;
    _turnHistory.clear();
    _findingCounts.clear();
    _scannerCounts.clear();
  }

  void _accumulate(GuardOutcome outcome) {
    for (final r in [...outcome.inputResults, ...outcome.outputResults]) {
      if (r.findings.isNotEmpty) {
        _scannerCounts[r.scanner] =
            (_scannerCounts[r.scanner] ?? 0) + r.findings.length;
      }
      for (final f in r.findings) {
        _findingCounts[f.type] = (_findingCounts[f.type] ?? 0) + 1;
      }
    }
  }
}
