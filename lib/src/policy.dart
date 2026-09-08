import 'dart:math' show max;

import 'scanner.dart';

/// A condition evaluated against scan findings.
///
/// Supports three aggregation modes over findings matching [pattern]:
/// - `count` — number of matching findings
/// - `maxScore` — highest confidence among matches
/// - `totalScore` — sum of confidence scores
///
/// JSON format:
/// ```json
/// {"count": "pii.*", "gt": 3}
/// {"any": "secret.*"}
/// {"maxScore": "injection.*", "gt": 0.8}
/// ```
class PolicyCondition {
  final String aggregate;
  final String pattern;
  final String operator;
  final double value;

  const PolicyCondition({
    required this.aggregate,
    required this.pattern,
    required this.operator,
    required this.value,
  });

  /// Parse from the `when` value of a policy rule JSON.
  factory PolicyCondition.fromJson(Map<String, dynamic> json) {
    const aggregates = {'count', 'maxScore', 'totalScore', 'any', 'none'};
    const operators = {'gt', 'gte', 'lt', 'lte', 'eq'};

    String? aggregate;
    String? pattern;
    String? op;
    double? value;

    for (final entry in json.entries) {
      if (aggregates.contains(entry.key)) {
        aggregate = entry.key;
        pattern = entry.value as String;
      } else if (operators.contains(entry.key)) {
        op = entry.key;
        value = (entry.value as num).toDouble();
      }
    }

    if (aggregate == null || pattern == null) {
      throw ArgumentError('Policy condition must specify an aggregate '
          '(count, maxScore, totalScore, any, none) and a finding pattern');
    }

    // `any` and `none` are shortcuts
    if (aggregate == 'any') {
      return PolicyCondition(
          aggregate: 'count', pattern: pattern, operator: 'gte', value: 1);
    }
    if (aggregate == 'none') {
      return PolicyCondition(
          aggregate: 'count', pattern: pattern, operator: 'eq', value: 0);
    }

    if (op == null || value == null) {
      throw ArgumentError('Policy condition with "$aggregate" requires a '
          'comparison operator (gt, gte, lt, lte, eq) and a numeric value');
    }
    return PolicyCondition(
        aggregate: aggregate, pattern: pattern, operator: op, value: value);
  }

  /// Evaluate this condition against a list of findings.
  bool evaluate(List<Finding> findings) {
    final matched = findings.where((f) => matchesGlob(f.type, pattern));

    final double actual;
    switch (aggregate) {
      case 'count':
        actual = matched.length.toDouble();
      case 'maxScore':
        actual = matched.isEmpty
            ? 0.0
            : matched.map((f) => f.confidence).reduce(max);
      case 'totalScore':
        actual = matched.fold(0.0, (sum, f) => sum + f.confidence);
      default:
        return false;
    }

    return switch (operator) {
      'gt' => actual > value,
      'gte' => actual >= value,
      'lt' => actual < value,
      'lte' => actual <= value,
      'eq' => actual == value,
      _ => false,
    };
  }

  Map<String, dynamic> toJson() => {aggregate: pattern, operator: value};
}

/// A rule that maps a [PolicyCondition] to a [GuardAction].
///
/// JSON format:
/// ```json
/// {"when": {"count": "pii.*", "gt": 3}, "then": "block"}
/// ```
class PolicyRule {
  final PolicyCondition condition;
  final GuardAction action;

  const PolicyRule({required this.condition, required this.action});

  factory PolicyRule.fromJson(Map<String, dynamic> json) {
    final when = json['when'];
    if (when is! Map<String, dynamic>) {
      throw ArgumentError('Policy rule must have a "when" object');
    }
    final thenStr = json['then'] as String?;
    if (thenStr == null) {
      throw ArgumentError('Policy rule must have a "then" action');
    }
    final action = switch (thenStr) {
      'block' => GuardAction.block,
      'warn' => GuardAction.warn,
      'redact' => GuardAction.redact,
      'hash' => GuardAction.hash,
      _ => throw ArgumentError('Unknown action in policy rule: $thenStr'),
    };
    return PolicyRule(
      condition: PolicyCondition.fromJson(when),
      action: action,
    );
  }

  /// Evaluate this rule against scan results. Returns [action] if the
  /// condition matches, `null` otherwise.
  GuardAction? evaluate(List<ScanResult> results) {
    final findings = [for (final r in results) ...r.findings];
    return condition.evaluate(findings) ? action : null;
  }

  Map<String, dynamic> toJson() => {
        'when': condition.toJson(),
        'then': action.name,
      };
}

/// Match a finding type against a glob pattern.
///
/// Supports:
/// - `*` — matches everything
/// - `prefix.*` — matches any type starting with `prefix.`
/// - exact match
bool matchesGlob(String type, String pattern) {
  if (pattern == '*') return true;
  if (pattern.endsWith('.*')) {
    return type.startsWith(pattern.substring(0, pattern.length - 1));
  }
  return type == pattern;
}
