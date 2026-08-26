import 'dart:convert';

import '../scanner.dart';
import 'code_execution_scanner.dart';
import 'prompt_injection_scanner.dart';

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

  /// Per-tool JSON Schema for argument validation.
  ///
  /// Keys are tool names; values are minimal JSON-Schema objects supporting
  /// `type`, `required`, and `properties` (same subset as [SchemaValidator]).
  /// Tools without an entry here skip argument validation.
  final Map<String, Map<String, dynamic>>? toolSchemas;

  /// When true, string argument values are scanned for injection patterns
  /// (shell, SQL, code, prompt injection). Walks nested maps/lists.
  final bool scanArguments;

  /// Max tool calls allowed in a single LLM turn (JSON array length).
  final int maxCallsPerTurn;

  /// Max nesting depth for chained tool calls. The caller provides the
  /// current [callStack]; if `callStack.length >= maxDepth`, all calls
  /// in this scan are blocked.
  final int maxDepth;

  /// The chain of tool names that led to this invocation, maintained by
  /// the orchestrator. Used for depth and circular-reference checks.
  final List<String> callStack;

  ToolCallScanner({
    this.action = GuardAction.block,
    this.allowedTools,
    this.deniedTools,
    this.toolSchemas,
    this.scanArguments = true,
    this.maxCallsPerTurn = 10,
    this.maxDepth = 5,
    this.callStack = const [],
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

    if (calls.length > maxCallsPerTurn) {
      findings.add(Finding(
        type: 'tool_call.max_calls_exceeded',
        match: '${calls.length}/$maxCallsPerTurn',
      ));
    }

    if (callStack.length >= maxDepth) {
      findings.add(Finding(
        type: 'tool_call.max_depth_exceeded',
        match: '${callStack.length}/$maxDepth',
      ));
    }

    for (final call in calls) {
      if (callStack.contains(call.name)) {
        findings.add(Finding(
          type: 'tool_call.circular_reference',
          match: call.name,
        ));
      }

      if (deniedTools != null && deniedTools!.contains(call.name)) {
        findings.add(Finding(type: 'tool_call.denied_name', match: call.name));
      } else if (allowedTools != null && !allowedTools!.contains(call.name)) {
        findings.add(Finding(type: 'tool_call.unknown_name', match: call.name));
      }

      if (toolSchemas != null) {
        final schema = toolSchemas![call.name];
        if (schema != null) {
          _validateArgs(call, schema, findings);
        }
      }

      if (scanArguments) {
        _scanArgInjection(call, findings);
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    final reason = findings.map((f) => '${f.type}(${f.match})').join(', ');

    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }

    return ScanResult.block(name, text, findings: findings, reason: reason);
  }

  static void _validateArgs(
      ToolCall call, Map<String, dynamic> schema, List<Finding> findings) {
    final args = call.arguments;
    final prefix = '${call.name}.';

    final required = schema['required'];
    if (required is List) {
      for (final k in required) {
        final key = k.toString();
        if (!args.containsKey(key)) {
          findings.add(Finding(
            type: 'tool_call.arg_missing_required',
            match: '$prefix$key',
          ));
        }
      }
    }

    final props = schema['properties'];
    if (props is Map) {
      for (final entry in props.entries) {
        final key = entry.key.toString();
        if (!args.containsKey(key)) continue;
        final spec = entry.value;
        if (spec is! Map) continue;
        final pType = spec['type'];
        if (pType is String && !_typeMatches(pType, args[key])) {
          findings.add(Finding(
            type: 'tool_call.arg_type_mismatch',
            match: '$prefix$key',
          ));
        }
      }
    }
  }

  static bool _typeMatches(String type, Object? value) => switch (type) {
        'object' => value is Map,
        'array' => value is List,
        'string' => value is String,
        'number' || 'integer' => value is num,
        'boolean' => value is bool,
        _ => true,
      };

  static void _scanArgInjection(ToolCall call, List<Finding> findings) {
    final strings = <(String, String)>[];
    for (final e in call.arguments.entries) {
      _collectStrings(e.value, '${call.name}.${e.key}', strings);
    }

    for (final (path, value) in strings) {
      final seen = <String>{};

      for (final p in CodeExecutionScanner.patterns) {
        final tag = _injectionTag(p.category);
        if (seen.contains(tag)) continue;
        if (p.regex.hasMatch(value)) {
          seen.add(tag);
          findings.add(Finding(
            type: 'tool_call.arg_injection.$tag',
            match: path,
          ));
        }
      }

      if (!seen.contains('prompt')) {
        for (final sig in kInjectionSignals) {
          if (sig.patterns.any((p) => p.hasMatch(value))) {
            findings.add(Finding(
              type: 'tool_call.arg_injection.prompt',
              match: path,
            ));
            break;
          }
        }
      }
    }
  }

  static String _injectionTag(CodeCategory c) => switch (c) {
        CodeCategory.shell || CodeCategory.filesystem => 'shell',
        CodeCategory.sql => 'sql',
        CodeCategory.injection => 'code',
      };

  static void _collectStrings(
    Object? value,
    String path,
    List<(String, String)> out,
  ) {
    if (value is String) {
      out.add((path, value));
    } else if (value is Map) {
      for (final e in value.entries) {
        _collectStrings(e.value, '$path.${e.key}', out);
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _collectStrings(value[i], '$path[$i]', out);
      }
    }
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
