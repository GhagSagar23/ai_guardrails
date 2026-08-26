import 'ai_guard.dart';

/// Escalation levels for [GuardSession].
enum EscalationLevel { warn, block, terminate }

/// Configures when [GuardSession] tightens enforcement based on accumulated
/// findings.
///
/// When total findings across all turns reach [blockThreshold], the session
/// escalates to [EscalationLevel.block] — any subsequent turn with findings
/// is force-blocked even if scanners would have passed. At
/// [terminateThreshold], the session refuses further runs entirely.
class EscalationPolicy {
  /// Total findings to escalate from warn → block.
  final int blockThreshold;

  /// Total findings to escalate from block → terminate.
  final int terminateThreshold;

  const EscalationPolicy({
    this.blockThreshold = 3,
    this.terminateThreshold = 5,
  });
}

/// Stateful multi-turn wrapper around [AiGuard].
///
/// Tracks turn count, accumulates findings, and optionally escalates
/// enforcement across a conversation. The wrapped [AiGuard] and its
/// scanners remain stateless — session state lives here.
class GuardSession {
  final AiGuard guard;

  /// Optional escalation policy. When null, no escalation occurs.
  final EscalationPolicy? escalationPolicy;

  int _turnCount = 0;
  final _turnHistory = <GuardOutcome>[];
  final _findingCounts = <String, int>{};
  final _scannerCounts = <String, int>{};
  EscalationLevel _escalationLevel = EscalationLevel.warn;

  GuardSession({required this.guard, this.escalationPolicy});

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

  /// Current escalation level.
  EscalationLevel get escalationLevel => _escalationLevel;

  /// Delegates to [guard.run], accumulates findings, applies escalation.
  Future<GuardOutcome> run({
    required String input,
    required Future<String> Function(String sanitizedInput) llmCall,
  }) async {
    if (_escalationLevel == EscalationLevel.terminate) {
      final outcome = const GuardOutcome(
        blocked: true,
        blockReason: 'Session terminated by escalation policy',
      );
      _turnCount++;
      _turnHistory.add(outcome);
      return outcome;
    }

    final atBlockLevel = _escalationLevel == EscalationLevel.block;

    var outcome = await guard.run(input: input, llmCall: llmCall);
    _turnCount++;
    _accumulate(outcome);

    if (atBlockLevel && !outcome.blocked && outcome.allFindings.isNotEmpty) {
      outcome = GuardOutcome(
        blocked: true,
        blockReason: 'Escalation policy: block level',
        input: outcome.input,
        piiMap: outcome.piiMap,
        inputResults: outcome.inputResults,
        outputResults: outcome.outputResults,
      );
    }

    _turnHistory.add(outcome);
    _updateEscalation();
    return outcome;
  }

  /// Resets all session state for reuse.
  void reset() {
    _turnCount = 0;
    _turnHistory.clear();
    _findingCounts.clear();
    _scannerCounts.clear();
    _escalationLevel = EscalationLevel.warn;
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

  void _updateEscalation() {
    if (escalationPolicy == null) return;
    final total = _findingCounts.values.fold<int>(0, (a, b) => a + b);
    if (total >= escalationPolicy!.terminateThreshold) {
      _escalationLevel = EscalationLevel.terminate;
    } else if (total >= escalationPolicy!.blockThreshold) {
      _escalationLevel = EscalationLevel.block;
    }
  }
}
