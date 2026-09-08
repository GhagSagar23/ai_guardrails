import '../scanner.dart';

/// Validates HTML output against tag and attribute allowlists.
///
/// Rejects tags not in [allowedTags] and strips dangerous attributes
/// (event handlers, javascript: URIs). Pure regex-based — no HTML parser dep.
class HtmlValidator implements Scanner {
  final Set<String> allowedTags;
  final Set<String> allowedAttributes;
  final GuardAction action;

  static const defaultTags = {
    'p', 'br', 'b', 'i', 'em', 'strong', 'a', 'ul', 'ol', 'li',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'code', 'pre', 'blockquote',
    'span', 'div', 'table', 'tr', 'td', 'th', 'thead', 'tbody', 'img',
    'hr', 'dl', 'dt', 'dd', 'sub', 'sup', 'mark', 'small', //
  };

  static const defaultAttributes = {
    'href', 'src', 'alt', 'title', 'class', 'id', 'width', 'height',
    'colspan', 'rowspan', 'target', 'rel', //
  };

  static final _tagPattern = RegExp(r'<\/?([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>');
  static final _attrPattern =
      RegExp(r'(\w[\w-]*)(?:\s*=\s*(?:"[^"]*"|' "'[^']*'" r'|\S+))?');
  static final _eventHandlerPattern =
      RegExp(r'\bon\w+\s*=', caseSensitive: false);
  static final _jsUriPattern = RegExp(
    '(?:href|src|action)\\s*=\\s*["\']?\\s*javascript:',
    caseSensitive: false,
  );

  HtmlValidator({
    Set<String>? allowedTags,
    Set<String>? allowedAttributes,
    this.action = GuardAction.block,
  })  : allowedTags = allowedTags ?? defaultTags,
        allowedAttributes = allowedAttributes ?? defaultAttributes;

  @override
  String get name => 'html_validator';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];

    for (final m in _tagPattern.allMatches(text)) {
      final tag = m.group(1)!.toLowerCase();
      if (!allowedTags.contains(tag)) {
        findings.add(Finding(
          type: 'html_validator.tag',
          start: m.start,
          end: m.end,
          match: tag,
        ));
      }

      final tagContent = m.group(0)!;

      if (_eventHandlerPattern.hasMatch(tagContent)) {
        findings.add(Finding(
          type: 'html_validator.event_handler',
          start: m.start,
          end: m.end,
          match: tagContent,
        ));
      }

      if (_jsUriPattern.hasMatch(tagContent)) {
        findings.add(Finding(
          type: 'html_validator.javascript_uri',
          start: m.start,
          end: m.end,
          match: tagContent,
        ));
      }

      if (!tagContent.startsWith('</')) {
        final attrPart =
            tagContent.substring(tagContent.indexOf(tag) + tag.length);
        for (final am in _attrPattern.allMatches(attrPart)) {
          final attr = am.group(1)!.toLowerCase();
          if (!allowedAttributes.contains(attr) &&
              !attr.startsWith('data-') &&
              attr != tag) {
            findings.add(Finding(
              type: 'html_validator.attribute',
              start: m.start,
              end: m.end,
              match: attr,
            ));
          }
        }
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final reason = '${findings.length} HTML violation(s)';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }
}
