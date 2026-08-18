import '../scanner.dart';

/// Categories of suspicious URL signals.
enum UrlCategory {
  ipLiteral,
  dataUri,
  javascriptUri,
  suspiciousTld,
  shortener,
  punycode,
  credentials,
}

/// Detects suspicious URLs in text: IP-literal hosts, data/javascript URIs,
/// phishing TLDs, URL shorteners, punycode (homograph), and embedded creds.
class UrlScanner implements Scanner {
  final GuardAction action;

  /// Categories to check. Default: all.
  final Set<UrlCategory> categories;

  UrlScanner({
    this.action = GuardAction.block,
    this.categories = const {
      UrlCategory.ipLiteral,
      UrlCategory.dataUri,
      UrlCategory.javascriptUri,
      UrlCategory.suspiciousTld,
      UrlCategory.shortener,
      UrlCategory.punycode,
      UrlCategory.credentials,
    },
  });

  @override
  String get name => 'url';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  static final _urlRe = RegExp(
    r'(?:https?://|ftp://|data:|javascript:)[^\s<>"\)}\]]+',
    caseSensitive: false,
  );

  // ponytail: regex covers common phishing TLDs, not exhaustive
  static final _suspiciousTlds = RegExp(
    r'\.(?:tk|ml|ga|cf|gq|buzz|top|click|link|zip|mov|cam|surf|icu|rest)\b',
    caseSensitive: false,
  );

  static final _shortenerHosts = RegExp(
    r'(?:bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|v\.gd|rb\.gy|shorturl\.at|cutt\.ly)\b',
    caseSensitive: false,
  );

  static final _ipHost = RegExp(
    r'://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
  );

  static final _credentials = RegExp(
    r'://[^@/\s]+:[^@/\s]+@',
  );

  static final _punycode = RegExp(
    r'://[^\s/]*xn--',
    caseSensitive: false,
  );

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];

    for (final m in _urlRe.allMatches(text)) {
      final url = m[0]!;
      final lower = url.toLowerCase();

      if (categories.contains(UrlCategory.dataUri) &&
          lower.startsWith('data:')) {
        findings.add(Finding(
          type: 'url.data_uri',
          start: m.start,
          end: m.end,
          match: url,
        ));
        continue;
      }

      if (categories.contains(UrlCategory.javascriptUri) &&
          lower.startsWith('javascript:')) {
        findings.add(Finding(
          type: 'url.javascript_uri',
          start: m.start,
          end: m.end,
          match: url,
        ));
        continue;
      }

      if (categories.contains(UrlCategory.credentials) &&
          _credentials.hasMatch(url)) {
        findings.add(Finding(
          type: 'url.credentials',
          start: m.start,
          end: m.end,
          match: url,
        ));
      }

      if (categories.contains(UrlCategory.ipLiteral) &&
          _ipHost.hasMatch(url)) {
        findings.add(Finding(
          type: 'url.ip_literal',
          start: m.start,
          end: m.end,
          match: url,
        ));
      }

      if (categories.contains(UrlCategory.punycode) &&
          _punycode.hasMatch(url)) {
        findings.add(Finding(
          type: 'url.punycode',
          start: m.start,
          end: m.end,
          match: url,
        ));
      }

      if (categories.contains(UrlCategory.shortener) &&
          _shortenerHosts.hasMatch(url)) {
        findings.add(Finding(
          type: 'url.shortener',
          start: m.start,
          end: m.end,
          match: url,
        ));
      }

      if (categories.contains(UrlCategory.suspiciousTld) &&
          _suspiciousTlds.hasMatch(url)) {
        findings.add(Finding(
          type: 'url.suspicious_tld',
          start: m.start,
          end: m.end,
          match: url,
        ));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    final passed = action == GuardAction.warn;
    final kinds = findings.map((f) => f.type).toSet().join(', ');
    return ScanResult(
      scanner: name,
      passed: passed,
      text: text,
      score: passed ? 0.5 : 1.0,
      findings: findings,
      reason: passed ? 'suspicious URLs detected ($kinds)' : 'blocked: $kinds',
    );
  }
}
