import 'dart:convert';

import '../scanner.dart';

/// Validates model output against a minimal JSON-Schema subset.
///
/// Supported keywords:
/// * top-level `type` — `object` | `array` | `string` | `number` | `boolean`
/// * `required` — list of keys that must be present (object only)
/// * `properties` — map of key → `{ "type": ... }` per-property type checks
///
/// A JSON parse error or any mismatch is a violation. Only [GuardAction.block]
/// and [GuardAction.warn] are meaningful; anything else is treated as block.
class SchemaValidator implements Scanner {
  /// The (minimal) JSON-Schema to enforce.
  final Map<String, dynamic> schema;

  /// Block on violation, or merely warn.
  final GuardAction action;

  SchemaValidator(this.schema, {this.action = GuardAction.block});

  @override
  String get name => 'schema';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    final reasons = <String>[];
    void violation(String kind, String message, {String? key}) {
      findings.add(Finding(type: 'schema.$kind', match: key, confidence: 1.0));
      reasons.add(message);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      violation('parse', 'invalid JSON: $e');
      return _result(text, findings, reasons);
    }

    final expectedType = schema['type'];
    if (expectedType is String && !_typeMatches(expectedType, decoded)) {
      violation('type', 'expected type "$expectedType"');
    }

    // final so promotion survives inside the forEach closure below.
    final Map<dynamic, dynamic>? obj = decoded is Map ? decoded : null;

    final required = schema['required'];
    if (required is List && obj != null) {
      for (final k in required) {
        final key = k.toString();
        if (!obj.containsKey(key)) {
          violation('required', 'missing required key "$key"', key: key);
        }
      }
    }

    final props = schema['properties'];
    if (props is Map && obj != null) {
      props.forEach((k, spec) {
        final key = k.toString();
        if (!obj.containsKey(key) || spec is! Map) return;
        final pType = spec['type'];
        if (pType is String && !_typeMatches(pType, obj[key])) {
          violation('property', 'property "$key" must be "$pType"', key: key);
        }
      });
    }

    return _result(text, findings, reasons);
  }

  ScanResult _result(
      String text, List<Finding> findings, List<String> reasons) {
    if (findings.isEmpty) return ScanResult.pass(name, text);
    final reason = 'schema validation failed: ${reasons.join('; ')}';
    if (action == GuardAction.warn) {
      return ScanResult(
        scanner: name,
        passed: true,
        text: text,
        score: 0.5,
        findings: findings,
        reason: reason,
      );
    }
    return ScanResult(
      scanner: name,
      passed: false,
      text: text,
      score: 1.0,
      findings: findings,
      reason: reason,
    );
  }

  bool _typeMatches(String type, Object? value) {
    switch (type) {
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      case 'string':
        return value is String;
      case 'number':
        return value is num;
      case 'boolean':
        return value is bool;
      default:
        return true; // unknown constraint => don't fail on it
    }
  }
}
