import '../scanner.dart';

/// One category of invisible/zero-width Unicode characters, defined by a
/// code-point predicate so the source stays free of literal invisible chars.
class InvisibleCategory {
  /// Category name, used in finding types as `invisible.<name>`.
  final String name;

  /// True when [codePoint] belongs to this category.
  final bool Function(int codePoint) contains;

  const InvisibleCategory(this.name, this.contains);
}

/// The invisible-character categories this scanner detects.
///
/// * `zero_width`  — U+200B..U+200D, U+FEFF, U+2060
/// * `bidi`        — U+202A..U+202E, U+2066..U+2069
/// * `soft_hyphen` — U+00AD
/// * `tag`         — U+E0000..U+E007F (astral tag block)
final List<InvisibleCategory> kInvisibleCategories = [
  InvisibleCategory(
    'zero_width',
    (c) =>
        c == 0x200B || c == 0x200C || c == 0x200D || c == 0xFEFF || c == 0x2060,
  ),
  InvisibleCategory(
    'bidi',
    (c) => (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069),
  ),
  InvisibleCategory('soft_hyphen', (c) => c == 0x00AD),
  InvisibleCategory('tag', (c) => c >= 0xE0000 && c <= 0xE007F),
];

/// Returns the category name for [codePoint], or `null` if it is visible.
String? _categorize(int codePoint) {
  for (final cat in kInvisibleCategories) {
    if (cat.contains(codePoint)) return cat.name;
  }
  return null;
}

/// Detects (and, by default, strips) invisible Unicode characters often used
/// to smuggle instructions past a human reviewer. Input-stage only.
///
/// Finding offsets are UTF-16 code-unit indices into the original text, so a
/// tag character (a surrogate pair) spans two units.
class InvisibleTextScanner implements Scanner {
  /// What to do with detected invisibles.
  final GuardAction action;

  const InvisibleTextScanner({this.action = GuardAction.redact});

  @override
  String get name => 'invisible_text';

  @override
  Set<ScanStage> get stages => const {ScanStage.input};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    final it = text.runes.iterator;
    while (it.moveNext()) {
      final cat = _categorize(it.current);
      if (cat == null) continue;
      findings.add(Finding(
        type: 'invisible.$cat',
        start: it.rawIndex,
        end: it.rawIndex + it.currentSize,
        match: it.currentAsString,
        confidence: 1.0,
      ));
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    switch (action) {
      case GuardAction.block:
        return ScanResult(
          scanner: name,
          passed: false,
          text: text,
          score: 1.0,
          findings: findings,
          reason: 'found ${findings.length} invisible character(s)',
        );

      case GuardAction.warn:
        return ScanResult(
          scanner: name,
          passed: true,
          text: text,
          score: 0.5,
          findings: findings,
          reason: 'found ${findings.length} invisible character(s)',
        );

      case GuardAction.redact:
        return ScanResult(
          scanner: name,
          passed: true,
          text: _rewrite(text, (_, __) => ''),
          score: 0.5,
          findings: findings,
          reason: 'stripped ${findings.length} invisible character(s)',
        );

      case GuardAction.hash:
        return ScanResult(
          scanner: name,
          passed: true,
          text: _rewrite(text, (cat, ch) => '[$cat:${_fnv1a(ch)}]'),
          score: 0.5,
          findings: findings,
          reason: 'tokenized ${findings.length} invisible character(s)',
        );
    }
  }

  /// Rebuilds [text], replacing each invisible char via [replace]
  /// (category, char) and leaving visible chars untouched.
  String _rewrite(String text, String Function(String cat, String ch) replace) {
    final buf = StringBuffer();
    final it = text.runes.iterator;
    while (it.moveNext()) {
      final cat = _categorize(it.current);
      buf.write(
          cat == null ? it.currentAsString : replace(cat, it.currentAsString));
    }
    return buf.toString();
  }
}

/// Tiny local FNV-1a (32-bit) → 6 hex chars. No crypto dependency.
String _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0').substring(2);
}
