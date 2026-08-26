import 'dart:convert';

import '../scanner.dart';

/// A tool/function call emitted by an LLM.
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({required this.name, this.arguments = const {}});

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw FormatException('ToolCall missing or empty "name"');
    }
    final args = json['arguments'];
    return ToolCall(
      name: name,
      arguments: args is Map<String, dynamic> ? args : const {},
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};

  @override
  String toString() => 'ToolCall($name, ${arguments.keys.join(', ')})';
}

/// Validates LLM-emitted tool/function calls before execution.
///
/// Accepts JSON text — a single `{"name": ..., "arguments": ...}` object or
/// an array of them. Validates tool names against optional allow/deny lists.
///
/// Malformed JSON or missing `name` fields are blocked (fail-closed).
///
/// This is an **output-stage** scanner: it checks what the model wants to
/// execute, not what the user typed.
class ToolCallScanner implements Scanner {
  final GuardAction action;

  /// When non-null, only these tool names are permitted.
  final Set<String>? allowedTools;

  /// Tool names that are always rejected, even if in [allowedTools].
  final Set<String>? deniedTools;

  ToolCallScanner({
    this.action = GuardAction.block,
    this.allowedTools,
    this.deniedTools,
  });

  @override
  String get name => 'tool_call';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final List<ToolCall> calls;
    try {
      calls = _parse(text);
    } on FormatException catch (e) {
      return ScanResult.block(
        name,
        text,
        reason: 'Malformed tool call JSON: $e',
        findings: [const Finding(type: 'tool_call.malformed')],
      );
    }

    if (calls.isEmpty) return ScanResult.pass(name, text);

    final findings = <Finding>[];

    for (final call in calls) {
      if (deniedTools != null && deniedTools!.contains(call.name)) {
        findings.add(Finding(type: 'tool_call.denied_name', match: call.name));
      } else if (allowedTools != null && !allowedTools!.contains(call.name)) {
        findings.add(Finding(type: 'tool_call.unknown_name', match: call.name));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    if (action == GuardAction.warn) {
      return ScanResult.warn(
        name,
        text,
        findings: findings,
        reason:
            'Tool call name violation: '
            '${findings.map((f) => '${f.type}(${f.match})').join(', ')}',
      );
    }

    return ScanResult.block(
      name,
      text,
      findings: findings,
      reason:
          'Tool call name violation: '
          '${findings.map((f) => '${f.type}(${f.match})').join(', ')}',
    );
  }

  /// Parse JSON text into a list of [ToolCall]s.
  ///
  /// Accepts a single object or an array of objects.
  static List<ToolCall> _parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      return [ToolCall.fromJson(decoded)];
    }
    if (decoded is List) {
      return decoded
          .cast<Map<String, dynamic>>()
          .map(ToolCall.fromJson)
          .toList();
    }
    throw const FormatException('Expected JSON object or array');
  }

  /// Parse tool calls from JSON text without scanning.
  ///
  /// Useful when other sub-issue scanners (#39–#41) need the parsed calls.
  static List<ToolCall> parseToolCalls(String text) => _parse(text);
}
