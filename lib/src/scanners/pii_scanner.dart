import '../data/pii_patterns.dart';
import '../scanner.dart';

/// Detects personally identifiable information and applies a [GuardAction].
///
/// Patterns are filtered by [locales] and, optionally, by bare [types]
/// (e.g. `{'email', 'credit_card'}`). Credit-card matches that fail a Luhn
/// checksum are dropped.
class PiiScanner implements Scanner {
  /// What to do with detected PII.
  final GuardAction action;

  /// If set, only these bare pattern types are scanned (e.g. `{'email'}`).
  final Set<String>? types;

  /// Locales whose patterns are active.
  final Set<PiiLocale> locales;

  /// Custom replacement for a redacted span; defaults to `[TYPE]`.
  final String Function(Finding)? placeholder;

  PiiScanner({
    this.action = GuardAction.redact,
    this.types,
    this.locales = const {PiiLocale.us, PiiLocale.eu, PiiLocale.india},
    this.placeholder,
  });

  @override
  String get name => 'pii';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  List<PiiPattern> get _active => kPiiPatterns
      .where((p) => p.locales.any(locales.contains))
      .where((p) => types == null || types!.contains(p.type))
      .toList();

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final patterns = _active;
    final raw = <Finding>[];
    for (final p in patterns) {
      for (final m in p.regex.allMatches(text)) {
        final matched = m[0]!;
        if (p.luhn && !_luhnValid(matched, p.luhnMinDigits)) continue;
        raw.add(Finding(
          type: 'pii.${p.type}',
          start: m.start,
          end: m.end,
          match: matched,
        ));
      }
    }

    final findings = _resolveOverlaps(raw);
    if (findings.isEmpty) return ScanResult.pass(name, text);

    switch (action) {
      case GuardAction.block:
        final kinds = findings.map((f) => f.type).toSet().join(', ');
        final score =
            findings.map((f) => f.confidence).reduce((a, b) => a > b ? a : b);
        return ScanResult(
          scanner: name,
          passed: false,
          text: text,
          score: score,
          findings: findings,
          reason: 'blocked: PII detected ($kinds)',
        );
      case GuardAction.warn:
        return ScanResult(
          scanner: name,
          passed: true,
          text: text,
          score: 0.5,
          findings: findings,
          reason: 'PII detected',
        );
      case GuardAction.redact:
      case GuardAction.hash:
        final hash = action == GuardAction.hash;
        final (transformed, rmap) = _transform(text, findings, hash);
        return ScanResult(
          scanner: name,
          passed: true,
          text: transformed,
          score: 0.5,
          findings: findings,
          reason: hash ? 'PII hashed' : 'PII redacted',
          redactionMap: rmap,
        );
    }
  }

  /// Drops findings whose span is covered by another finding, so a single
  /// piece of data is reported (and later redacted) once. Leftmost-longest
  /// wins; order is stabilised so results don't depend on the pattern list.
  static List<Finding> _resolveOverlaps(List<Finding> raw) {
    if (raw.length < 2) return raw;
    final sorted = [...raw]..sort((a, b) {
        if (a.start != b.start) return a.start - b.start;
        return (b.end - b.start) - (a.end - a.start); // longer first
      });
    final kept = <Finding>[];
    var coveredTo = -1;
    for (final f in sorted) {
      if (f.start < coveredTo) continue; // overlaps a kept span
      kept.add(f);
      if (f.end > coveredTo) coveredTo = f.end;
    }
    return kept;
  }

  /// Rebuilds [text] with each resolved [findings] span replaced by its
  /// placeholder, and returns the placeholder→original map for rehydration.
  (String, Map<String, String>) _transform(
      String text, List<Finding> findings, bool hash) {
    final buf = StringBuffer();
    final map = <String, String>{};
    final counts = <String, int>{};
    var cursor = 0;
    for (final f in findings) {
      buf.write(text.substring(cursor, f.start));
      final bare = f.type.startsWith('pii.') ? f.type.substring(4) : f.type;
      final idx = counts[bare] = (counts[bare] ?? 0) + 1;
      final token = _placeholderFor(bare, f.match ?? '', hash, idx);
      map[token] = f.match ?? '';
      buf.write(token);
      cursor = f.end;
    }
    buf.write(text.substring(cursor));
    return (buf.toString(), map);
  }

  String _placeholderFor(String type, String match, bool hash, int index) {
    if (hash) return '[${type.toUpperCase()}:${_fnv6(match)}]';
    if (placeholder != null) {
      return placeholder!(Finding(type: 'pii.$type', match: match));
    }
    return '[${type.toUpperCase()}_$index]';
  }

  /// 24-bit FNV-1a of [s] as 6 hex chars — a stable, non-reversible token.
  static String _fnv6(String s) {
    var hash = 0x811c9dc5;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return (hash & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }

  /// Luhn checksum over the digits of [s]; runs shorter than [minDigits] are rejected.
  static bool _luhnValid(String s, [int minDigits = 12]) {
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < minDigits) return false;
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (alt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      alt = !alt;
    }
    return sum % 10 == 0;
  }
}
