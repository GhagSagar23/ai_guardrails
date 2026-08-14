import '../scanner.dart';

/// Flags any text matching one of a caller-supplied list of [Pattern]s.
///
/// A [Pattern] is either a plain [String] (literal substring match) or a
/// [RegExp], so callers control precision entirely. Findings use the
/// `banned_pattern.match` type. The scanner name is configurable so several
/// instances (e.g. `profanity`, `competitor_names`) can coexist in one
/// pipeline with distinct result names.
class BannedPatternScanner implements Scanner {
  final List<Pattern> patterns;
  final GuardAction action;
  final String _name;

  BannedPatternScanner(
    this.patterns, {
    this.action = GuardAction.block,
    String name = 'banned_pattern',
  }) : _name = name;

  @override
  String get name => _name;

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    for (final p in patterns) {
      for (final m in p.allMatches(text)) {
        findings.add(Finding(
          type: 'banned_pattern.match',
          start: m.start,
          end: m.end,
          match: m[0],
        ));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    findings.sort((a, b) => a.start.compareTo(b.start));

    switch (action) {
      case GuardAction.block:
        return ScanResult(
          scanner: name,
          passed: false,
          text: text,
          score: 1.0,
          findings: findings,
          reason: 'blocked: ${findings.length} banned pattern(s) matched',
        );
      case GuardAction.redact:
        return ScanResult(
          scanner: name,
          passed: true,
          text: _transform(text, hashed: false),
          score: 0.5,
          findings: findings,
          reason: 'redacted ${findings.length} banned pattern(s)',
        );
      case GuardAction.hash:
        return ScanResult(
          scanner: name,
          passed: true,
          text: _transform(text, hashed: true),
          score: 0.5,
          findings: findings,
          reason: 'hashed ${findings.length} banned pattern(s)',
        );
      case GuardAction.warn:
        return ScanResult(
          scanner: name,
          passed: true,
          text: text,
          score: 0.5,
          findings: findings,
          reason: 'warning: ${findings.length} banned pattern(s) matched',
        );
    }
  }

  String _transform(String text, {required bool hashed}) {
    var out = text;
    for (final p in patterns) {
      out = out.replaceAllMapped(
        p,
        (m) => hashed ? '[BANNED:${_fnv1a(m[0]!)}]' : '[BANNED]',
      );
    }
    return out;
  }
}

/// Tiny local FNV-1a (32-bit) → 6 hex chars. Stable, non-cryptographic;
/// only used to make hashed placeholders deterministic without a dependency.
String _fnv1a(String s) {
  var hash = 0x811c9dc5;
  for (final c in s.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0').substring(2);
}
