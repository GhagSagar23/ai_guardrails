import '../scanner.dart';

/// Validates SQL output against a statement-type allowlist.
///
/// Default allows only `SELECT`. Detects dangerous statements (DROP, ALTER,
/// DELETE, TRUNCATE, EXEC, etc.) even when embedded in multi-statement strings.
class SqlValidator implements Scanner {
  final Set<String> allowedStatements;
  final GuardAction action;

  static const defaultAllowed = {'SELECT'};

  // ponytail: match statement keywords at word boundary, case-insensitive
  static final _statementPattern = RegExp(
    r'\b(SELECT|INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|MERGE|REPLACE|CALL|LOAD|COPY|VACUUM|REINDEX|ATTACH|DETACH)\b',
    caseSensitive: false,
  );

  static final _commentPattern = RegExp(
    r'--[^\n]*|/\*[\s\S]*?\*/',
  );

  SqlValidator({
    Set<String>? allowedStatements,
    this.action = GuardAction.block,
  }) : allowedStatements = allowedStatements ?? defaultAllowed;

  @override
  String get name => 'sql_validator';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final stripped = text.replaceAll(_commentPattern, ' ');
    final findings = <Finding>[];

    for (final m in _statementPattern.allMatches(stripped)) {
      final stmt = m.group(1)!.toUpperCase();
      if (!allowedStatements.contains(stmt)) {
        findings.add(Finding(
          type: 'sql_validator.$stmt',
          start: m.start,
          end: m.end,
          match: m.group(0),
        ));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final blocked = findings.map((f) => f.type.split('.').last).toSet();
    final reason = 'disallowed SQL statement(s): ${blocked.join(', ')}';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }
}
