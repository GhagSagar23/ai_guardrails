import '../fnv.dart';
import '../scanner.dart';

/// Detects mentions of competitor names/products in generated text.
///
/// Similar mechanics to [BannedTopicScanner] but semantically distinct —
/// for brand-safety use cases where competitor mentions must be flagged.
class CompetitorMentionScanner implements Scanner {
  final List<String> competitors;
  final GuardAction action;
  final bool caseSensitive;

  final List<RegExp> _patterns;

  CompetitorMentionScanner(
    this.competitors, {
    this.action = GuardAction.block,
    this.caseSensitive = false,
  }) : _patterns = [
          for (final c in competitors)
            RegExp('\\b${RegExp.escape(c)}\\b', caseSensitive: caseSensitive),
        ];

  @override
  String get name => 'competitor_mention';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    final matched = <String>{};

    for (var i = 0; i < competitors.length; i++) {
      for (final m in _patterns[i].allMatches(text)) {
        findings.add(Finding(
          type: 'competitor.${competitors[i]}',
          start: m.start,
          end: m.end,
          match: m.group(0),
        ));
        matched.add(competitors[i]);
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    switch (action) {
      case GuardAction.block:
        return ScanResult.block(
          name,
          text,
          findings: findings,
          reason: 'competitor mention(s): ${matched.join(', ')}',
        );
      case GuardAction.redact:
        var out = text;
        for (final p in _patterns) {
          out = out.replaceAllMapped(p, (_) => '[COMPETITOR]');
        }
        return ScanResult.warn(
          name,
          out,
          findings: findings,
          reason: 'redacted ${findings.length} competitor mention(s)',
        );
      case GuardAction.hash:
        var out = text;
        for (final p in _patterns) {
          out = out.replaceAllMapped(
              p, (m) => '[COMPETITOR:${fnv1a(m.group(0)!)}]');
        }
        return ScanResult.warn(
          name,
          out,
          findings: findings,
          reason: 'hashed ${findings.length} competitor mention(s)',
        );
      case GuardAction.transform:
      case GuardAction.warn:
        return ScanResult.warn(name, text, findings: findings);
    }
  }
}
