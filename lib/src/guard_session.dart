import 'dart:math' show max;

import 'ai_guard.dart';

/// Escalation levels for [GuardSession].
enum EscalationLevel { warn, block, terminate }

/// Per-finding-type escalation thresholds.
///
/// Attach to [EscalationPolicy.typeRules] keyed by finding type or glob
/// pattern (e.g. `pii.*` matches `pii.email`, `pii.ssn`, etc.).
class EscalationRule {
  final int blockThreshold;
  final int terminateThreshold;

  const EscalationRule({
    required this.blockThreshold,
    required this.terminateThreshold,
  });

  Map<String, dynamic> toJson() => {
        'blockThreshold': blockThreshold,
        'terminateThreshold': terminateThreshold,
      };

  factory EscalationRule.fromJson(Map<String, dynamic> json) => EscalationRule(
        blockThreshold: json['blockThreshold'] as int,
        terminateThreshold: json['terminateThreshold'] as int,
      );
}

/// Configures when [GuardSession] tightens enforcement based on accumulated
/// findings.
///
/// When total findings across all turns reach [blockThreshold], the session
/// escalates to [EscalationLevel.block] — any subsequent turn with findings
/// is force-blocked even if scanners would have passed. At
/// [terminateThreshold], the session refuses further runs entirely.
///
/// [typeRules] override global thresholds for specific finding types.
/// Keys are exact type strings (`pii.email`) or glob patterns (`pii.*`).
/// Exact match takes priority; `pii.*` matches any type starting with `pii.`.
///
/// When [window] is set, only the last [window] turns count toward
/// escalation — older violations decay. Without it, escalation is monotonic
/// (never de-escalates without [GuardSession.reset]).
class EscalationPolicy {
  /// Total findings to escalate from warn → block.
  final int blockThreshold;

  /// Total findings to escalate from block → terminate.
  final int terminateThreshold;

  /// Per-finding-type overrides. Keys: exact type or `prefix.*` glob.
  final Map<String, EscalationRule> typeRules;

  /// When set, only the last [window] turns count toward escalation.
  final int? window;

  const EscalationPolicy({
    this.blockThreshold = 3,
    this.terminateThreshold = 5,
    this.typeRules = const {},
    this.window,
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

  /// Called when escalation level changes.
  final void Function(EscalationLevel from, EscalationLevel to)? onEscalation;

  int _turnCount = 0;
  final _turnHistory = <GuardOutcome>[];
  final _findingCounts = <String, int>{};
  final _scannerCounts = <String, int>{};
  final _turnFindingSnapshots = <Map<String, int>>[];
  EscalationLevel _escalationLevel = EscalationLevel.warn;

  GuardSession({
    required this.guard,
    this.escalationPolicy,
    this.onEscalation,
  });

  /// Restore a session from a previously exported [toJson] snapshot.
  ///
  /// The [guard] and [escalationPolicy] must be provided separately — they
  /// contain runtime objects (scanner instances) that are not serializable.
  /// [turnHistory] is NOT restored (it contains text); only the escalation
  /// metadata needed for continued operation is restored.
  factory GuardSession.restore({
    required AiGuard guard,
    required Map<String, dynamic> state,
    EscalationPolicy? escalationPolicy,
    void Function(EscalationLevel, EscalationLevel)? onEscalation,
  }) {
    final session = GuardSession(
      guard: guard,
      escalationPolicy: escalationPolicy,
      onEscalation: onEscalation,
    );
    session._turnCount = state['turnCount'] as int;
    session._escalationLevel =
        EscalationLevel.values.byName(state['escalationLevel'] as String);

    final fc = state['findingCounts'] as Map<String, dynamic>?;
    if (fc != null) {
      session._findingCounts.addAll(fc.cast<String, int>());
    }
    final sc = state['scannerCounts'] as Map<String, dynamic>?;
    if (sc != null) {
      session._scannerCounts.addAll(sc.cast<String, int>());
    }
    final snaps = state['turnFindingSnapshots'] as List?;
    if (snaps != null) {
      session._turnFindingSnapshots.addAll(
        snaps.map((e) => (e as Map<String, dynamic>).cast<String, int>()),
      );
    }
    return session;
  }

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
      _turnFindingSnapshots.add(const {});
      _turnHistory.add(outcome);
      // ponytail: with window, terminated turns advance the window so
      // old violations can decay; without window this is a no-op.
      if (escalationPolicy?.window != null) _updateEscalation();
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
    _turnFindingSnapshots.clear();
    _escalationLevel = EscalationLevel.warn;
  }

  /// Serializes session state for persistence across server restarts.
  ///
  /// Does NOT include [turnHistory] (it contains user text). Includes
  /// everything needed for escalation to resume correctly.
  Map<String, dynamic> toJson() => {
        'turnCount': _turnCount,
        'findingCounts': Map<String, int>.from(_findingCounts),
        'scannerCounts': Map<String, int>.from(_scannerCounts),
        'escalationLevel': _escalationLevel.name,
        'turnFindingSnapshots':
            _turnFindingSnapshots.map((s) => Map<String, int>.from(s)).toList(),
      };

  void _accumulate(GuardOutcome outcome) {
    final turnSnapshot = <String, int>{};
    for (final r in [...outcome.inputResults, ...outcome.outputResults]) {
      if (r.findings.isNotEmpty) {
        _scannerCounts[r.scanner] =
            (_scannerCounts[r.scanner] ?? 0) + r.findings.length;
      }
      for (final f in r.findings) {
        _findingCounts[f.type] = (_findingCounts[f.type] ?? 0) + 1;
        turnSnapshot[f.type] = (turnSnapshot[f.type] ?? 0) + 1;
      }
    }
    _turnFindingSnapshots.add(turnSnapshot);
  }

  void _updateEscalation() {
    if (escalationPolicy == null) return;
    final policy = escalationPolicy!;

    final counts = policy.window != null
        ? _windowedCounts(policy.window!)
        : _findingCounts;

    var highest = EscalationLevel.warn;

    for (final entry in policy.typeRules.entries) {
      final count = _countMatchingType(counts, entry.key);
      if (count >= entry.value.terminateThreshold) {
        highest = EscalationLevel.terminate;
        break;
      }
      if (count >= entry.value.blockThreshold &&
          highest.index < EscalationLevel.block.index) {
        highest = EscalationLevel.block;
      }
    }

    if (highest != EscalationLevel.terminate) {
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      if (total >= policy.terminateThreshold) {
        highest = EscalationLevel.terminate;
      } else if (total >= policy.blockThreshold &&
          highest.index < EscalationLevel.block.index) {
        highest = EscalationLevel.block;
      }
    }

    _setEscalation(highest);
  }

  Map<String, int> _windowedCounts(int window) {
    final start = max(0, _turnFindingSnapshots.length - window);
    final counts = <String, int>{};
    for (var i = start; i < _turnFindingSnapshots.length; i++) {
      for (final entry in _turnFindingSnapshots[i].entries) {
        counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
      }
    }
    return counts;
  }

  static int _countMatchingType(Map<String, int> counts, String pattern) {
    if (pattern.endsWith('.*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      var total = 0;
      for (final e in counts.entries) {
        if (e.key.startsWith(prefix)) total += e.value;
      }
      return total;
    }
    return counts[pattern] ?? 0;
  }

  void _setEscalation(EscalationLevel level) {
    if (level == _escalationLevel) return;
    // Without window: monotonic — only escalate, never de-escalate.
    // With window: allow de-escalation as old violations decay.
    if (escalationPolicy?.window == null &&
        level.index < _escalationLevel.index) {
      return;
    }
    final from = _escalationLevel;
    _escalationLevel = level;
    onEscalation?.call(from, level);
  }
}
