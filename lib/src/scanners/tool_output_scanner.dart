import 'dart:convert';

import '../scanner.dart';

/// Categories of dangerous patterns in tool execution results.
enum ToolOutputCategory { xss, templateInjection, pathTraversal, ssrf }

/// Pattern: a regex, finding type, and category.
class ToolOutputPattern {
  final ToolOutputCategory category;
  final String type;
  final RegExp regex;
  const ToolOutputPattern(this.category, this.type, this.regex);
}

/// Detects injection attacks in tool execution results before they reach
/// the LLM context or end user.
///
/// Covers XSS, server-side template injection (SSTI), path traversal,
/// and SSRF indicators. Complements [ToolCallScanner] (which validates
/// tool *inputs*) by scanning tool *outputs* — critical for agentic
/// pipelines where tools query untrusted data sources.
///
/// For SQL and shell injection in tool outputs, compose with
/// [CodeExecutionScanner] in the same pipeline.
class ToolOutputScanner implements Scanner {
  final GuardAction action;

  /// Categories to check. Default: all.
  final Set<ToolOutputCategory> categories;

  ToolOutputScanner({
    this.action = GuardAction.block,
    this.categories = const {
      ToolOutputCategory.xss,
      ToolOutputCategory.templateInjection,
      ToolOutputCategory.pathTraversal,
      ToolOutputCategory.ssrf,
    },
  });

  @override
  String get name => 'tool_output';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  static final patterns = <ToolOutputPattern>[
    // XSS
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'<script[\s>]', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'javascript\s*:', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp('\\bon\\w+\\s*=\\s*["\']', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'<iframe[\s>]', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'<object[\s>]', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'<embed[\s>]', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'<svg[^>]*\bon', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.xss, 'tool_output.xss',
        RegExp(r'expression\s*\(', caseSensitive: false)),

    // Template injection (SSTI)
    ToolOutputPattern(
        ToolOutputCategory.templateInjection,
        'tool_output.template_injection',
        RegExp(r'\{%\s*\w+', caseSensitive: false)),
    ToolOutputPattern(
        ToolOutputCategory.templateInjection,
        'tool_output.template_injection',
        RegExp(r'<%[=-]?\s*', caseSensitive: false)),
    ToolOutputPattern(
        ToolOutputCategory.templateInjection,
        'tool_output.template_injection',
        RegExp(r'\{\{\s*config\b', caseSensitive: false)),
    ToolOutputPattern(
        ToolOutputCategory.templateInjection,
        'tool_output.template_injection',
        RegExp(r'\{\{\s*request\b', caseSensitive: false)),
    ToolOutputPattern(
        ToolOutputCategory.templateInjection,
        'tool_output.template_injection',
        RegExp(r'__class__|__mro__|__subclasses__', caseSensitive: false)),
    ToolOutputPattern(
        ToolOutputCategory.templateInjection,
        'tool_output.template_injection',
        RegExp(r'<#\w+', caseSensitive: false)),

    // Path traversal
    ToolOutputPattern(ToolOutputCategory.pathTraversal,
        'tool_output.path_traversal', RegExp(r'\.\.[/\\]')),
    ToolOutputPattern(
        ToolOutputCategory.pathTraversal,
        'tool_output.path_traversal',
        RegExp(r'%2e%2e[%/\\]', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.pathTraversal,
        'tool_output.path_traversal', RegExp(r'%00')),

    // SSRF indicators
    ToolOutputPattern(ToolOutputCategory.ssrf, 'tool_output.ssrf',
        RegExp(r'169\.254\.169\.254')),
    ToolOutputPattern(ToolOutputCategory.ssrf, 'tool_output.ssrf',
        RegExp(r'\bfile://', caseSensitive: false)),
    ToolOutputPattern(ToolOutputCategory.ssrf, 'tool_output.ssrf',
        RegExp(r'\bgopher://', caseSensitive: false)),
  ];

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final strings = _extractStrings(text);
    final findings = <Finding>[];

    for (final s in strings) {
      for (final p in patterns) {
        if (!categories.contains(p.category)) continue;
        for (final m in p.regex.allMatches(s)) {
          findings.add(Finding(
            type: p.type,
            start: m.start,
            end: m.end,
            match: m[0],
          ));
        }
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    final reason =
        'tool output injection detected: ${findings.map((f) => f.type).toSet().join(', ')}';

    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }

  /// Extract scannable strings from [text].
  ///
  /// If [text] is valid JSON, walks the structure and collects all string
  /// values (recursive into objects and arrays). Otherwise returns [text]
  /// as a single-element list.
  static List<String> _extractStrings(String text) {
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      final strings = <String>[];
      _collectStrings(decoded, strings);
      return strings.isEmpty ? [text] : strings;
    } on FormatException {
      return [text];
    }
  }

  static void _collectStrings(Object? value, List<String> out) {
    if (value is String) {
      out.add(value);
    } else if (value is Map) {
      for (final v in value.values) {
        _collectStrings(v, out);
      }
    } else if (value is List) {
      for (final v in value) {
        _collectStrings(v, out);
      }
    }
  }
}
