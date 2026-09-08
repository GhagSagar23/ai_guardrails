import '../scanner.dart';

/// Validates URLs in text against protocol/domain allowlists and credential checks.
///
/// Extracts URLs from text and validates each: protocol must be in
/// [allowedProtocols], domain in [allowedDomains] (if set), no userinfo
/// (credentials) in the URI.
class UrlFormatValidator implements Scanner {
  final Set<String> allowedProtocols;
  final Set<String>? allowedDomains;
  final bool blockCredentials;
  final GuardAction action;

  static final _urlPattern = RegExp(
    r'https?://[^\s<>"]+|ftp://[^\s<>"]+',
    caseSensitive: false,
  );

  UrlFormatValidator({
    Set<String>? allowedProtocols,
    this.allowedDomains,
    this.blockCredentials = true,
    this.action = GuardAction.block,
  }) : allowedProtocols = allowedProtocols ?? const {'http', 'https'};

  @override
  String get name => 'url_format_validator';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];

    for (final m in _urlPattern.allMatches(text)) {
      final raw = m.group(0)!;
      final uri = Uri.tryParse(raw);
      if (uri == null) {
        findings.add(Finding(
          type: 'url_format_validator.parse',
          start: m.start,
          end: m.end,
          match: raw,
        ));
        continue;
      }

      if (!allowedProtocols.contains(uri.scheme.toLowerCase())) {
        findings.add(Finding(
          type: 'url_format_validator.protocol',
          start: m.start,
          end: m.end,
          match: uri.scheme,
        ));
      }

      if (allowedDomains != null &&
          !allowedDomains!.contains(uri.host.toLowerCase())) {
        findings.add(Finding(
          type: 'url_format_validator.domain',
          start: m.start,
          end: m.end,
          match: uri.host,
        ));
      }

      if (blockCredentials && uri.userInfo.isNotEmpty) {
        findings.add(Finding(
          type: 'url_format_validator.credentials',
          start: m.start,
          end: m.end,
        ));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final reason = '${findings.length} URL violation(s)';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }
}
