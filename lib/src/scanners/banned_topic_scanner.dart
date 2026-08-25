import '../fnv.dart';
import '../scanner.dart';

/// Blocks/redacts text that mentions any configured banned topic phrase.
///
/// Each topic is matched on word boundaries (multi-word phrases allowed) so
/// `gun` does not fire inside `Burgundy`. Honors every [GuardAction]:
/// * [GuardAction.block]  — reject with a reason listing the matched topics.
/// * [GuardAction.redact] — replace each match with `[TOPIC]`.
/// * [GuardAction.hash]   — replace each match with `[TOPIC:ab12cd]`.
/// * [GuardAction.warn]   — keep findings, pass the text through unchanged.
class BannedTopicScanner implements Scanner {
  /// The banned phrases, used verbatim in finding types (`topic.<topic>`).
  final List<String> topics;

  /// What to do when a topic is found.
  final GuardAction action;

  /// Whether matching respects letter case.
  final bool caseSensitive;

  final List<RegExp> _patterns;

  BannedTopicScanner(
    this.topics, {
    this.action = GuardAction.block,
    this.caseSensitive = false,
  }) : _patterns = [
          // ponytail: \b word-boundary — right for word phrases; a topic that
          // starts/ends with punctuation (e.g. "c++") won't anchor. Swap to
          // lookarounds if such topics are ever needed.
          for (final t in topics)
            RegExp('\\b${RegExp.escape(t)}\\b', caseSensitive: caseSensitive),
        ];

  @override
  String get name => 'banned_topic';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    final matched = <String>{};
    for (var i = 0; i < topics.length; i++) {
      for (final m in _patterns[i].allMatches(text)) {
        findings.add(Finding(
          type: 'topic.${topics[i]}',
          start: m.start,
          end: m.end,
          match: m.group(0),
          confidence: 1.0,
        ));
        matched.add(topics[i]);
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    switch (action) {
      case GuardAction.block:
        final score = findings.fold<double>(
            0, (a, f) => f.confidence > a ? f.confidence : a);
        return ScanResult.block(
          name,
          text,
          score: score,
          findings: findings,
          reason: 'banned topic(s): ${matched.join(', ')}',
        );
      case GuardAction.redact:
        var out = text;
        for (final p in _patterns) {
          out = out.replaceAllMapped(p, (_) => '[TOPIC]');
        }
        return ScanResult.warn(
          name,
          out,
          findings: findings,
          reason: 'redacted ${findings.length} topic match(es)',
        );
      case GuardAction.hash:
        var out = text;
        for (final p in _patterns) {
          out = out.replaceAllMapped(p, (m) => '[TOPIC:${fnv1a(m.group(0)!)}]');
        }
        return ScanResult.warn(
          name,
          out,
          findings: findings,
          reason: 'hashed ${findings.length} topic match(es)',
        );
      case GuardAction.warn:
        return ScanResult.warn(name, text, findings: findings);
    }
  }
}
