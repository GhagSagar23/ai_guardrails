import '../scanner.dart';

/// One secret-detection rule: a dotted `kind` and the pattern that finds it.
///
/// For every rule the sensitive token ends at the match end; [tokenStart]
/// returns where it begins. That lets contextual rules (e.g. `aws_secret`,
/// whose regex also consumes nearby context) redact only the secret itself
/// while keeping the surrounding words intact.
class _SecretRule {
  final String kind;
  final RegExp regex;
  final double confidence;
  final int Function(Match m) tokenStart;
  const _SecretRule(
    this.kind,
    this.regex,
    this.tokenStart, {
    this.confidence = 1.0,
  });
}

int _wholeMatch(Match m) => m.start;

/// Detects hard-coded credentials (API keys, tokens, private keys) in text.
///
/// Patterns are deliberately narrow to avoid false positives on ordinary
/// prose. Findings use the `secret.<kind>` type. The matched substring is
/// never echoed in [Finding.match] (it would leak the secret); use the
/// char offsets to locate it in the original text.
class SecretScanner implements Scanner {
  final GuardAction action;

  SecretScanner({this.action = GuardAction.block});

  @override
  String get name => 'secret';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  /// The detection rules, in redaction order. Order only matters for the
  /// (cosmetic) sequence of replacements; findings are computed independently.
  static final List<_SecretRule> _rules = [
    _SecretRule(
      'aws_access_key',
      RegExp(r'AKIA[A-Z0-9]{16}'),
      _wholeMatch,
    ),
    // Contextual: the word "aws" within 40 chars before a 40-char base64-ish
    // blob. The token is always the trailing 40 chars of the match.
    _SecretRule(
      'aws_secret',
      RegExp(r'aws[\s\S]{0,40}?[A-Za-z0-9/+]{40}', caseSensitive: false),
      (m) => m.end - 40,
      confidence: 0.8,
    ),
    _SecretRule(
      'gcp_api_key',
      RegExp(r'AIza[A-Za-z0-9_-]{35}'),
      _wholeMatch,
    ),
    _SecretRule(
      'github_token',
      RegExp(r'gh[pousr]_[A-Za-z0-9]{36,}'),
      _wholeMatch,
    ),
    _SecretRule(
      'openai_key',
      RegExp(r'sk-[A-Za-z0-9]{20,}'),
      _wholeMatch,
    ),
    _SecretRule(
      'slack_token',
      RegExp(r'xox[baprs]-[A-Za-z0-9-]{10,}'),
      _wholeMatch,
    ),
    _SecretRule(
      'jwt',
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      _wholeMatch,
    ),
    _SecretRule(
      'private_key_block',
      RegExp(
        r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
      ),
      _wholeMatch,
    ),
  ];

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    for (final rule in _rules) {
      for (final m in rule.regex.allMatches(text)) {
        findings.add(Finding(
          type: 'secret.${rule.kind}',
          start: rule.tokenStart(m),
          end: m.end,
          confidence: rule.confidence,
        ));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    findings.sort((a, b) => a.start.compareTo(b.start));

    switch (action) {
      case GuardAction.block:
        final kinds = {for (final f in findings) f.type.split('.').last};
        final score =
            findings.map((f) => f.confidence).reduce((a, b) => a > b ? a : b);
        return ScanResult(
          scanner: name,
          passed: false,
          text: text,
          score: score,
          findings: findings,
          reason: 'blocked: secret(s) detected: ${kinds.join(', ')}',
        );
      case GuardAction.redact:
        return ScanResult(
          scanner: name,
          passed: true,
          text: _transform(text, hashed: false),
          score: 0.5,
          findings: findings,
          reason: 'redacted ${findings.length} secret(s)',
        );
      case GuardAction.hash:
        return ScanResult(
          scanner: name,
          passed: true,
          text: _transform(text, hashed: true),
          score: 0.5,
          findings: findings,
          reason: 'hashed ${findings.length} secret(s)',
        );
      case GuardAction.warn:
        return ScanResult(
          scanner: name,
          passed: true,
          text: text,
          score: 0.5,
          findings: findings,
          reason: 'warning: ${findings.length} secret(s) detected',
        );
    }
  }

  /// Replace each secret's trailing token with a placeholder, rule by rule,
  /// preserving any leading context the rule's regex consumed.
  String _transform(String text, {required bool hashed}) {
    var out = text;
    for (final rule in _rules) {
      out = out.replaceAllMapped(rule.regex, (m) {
        final localStart = rule.tokenStart(m) - m.start;
        final prefix = m[0]!.substring(0, localStart);
        final token = m[0]!.substring(localStart);
        final label = rule.kind.toUpperCase();
        final replacement = hashed ? '[$label:${_fnv1a(token)}]' : '[$label]';
        return prefix + replacement;
      });
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
