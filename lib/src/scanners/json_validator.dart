import 'dart:convert';

import '../scanner.dart';

/// Validates that text is well-formed JSON with configurable structural limits.
///
/// Unlike [SchemaValidator] (which checks shape), this checks syntax and
/// structural constraints: nesting depth, array length, key count.
class JsonValidator implements Scanner {
  final int maxDepth;
  final int maxArrayLength;
  final int maxKeyCount;
  final GuardAction action;

  JsonValidator({
    this.maxDepth = 64,
    this.maxArrayLength = 10000,
    this.maxKeyCount = 1000,
    this.action = GuardAction.block,
  });

  @override
  String get name => 'json_validator';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      findings.add(const Finding(type: 'json_validator.parse'));
      return _result(text, findings, 'invalid JSON syntax');
    }

    _walk(decoded, 0, findings);

    if (findings.isEmpty) return ScanResult.pass(name, text);
    return _result(
      text,
      findings,
      '${findings.length} structural violation(s)',
    );
  }

  void _walk(dynamic value, int depth, List<Finding> findings) {
    if (depth > maxDepth) {
      findings.add(Finding(
        type: 'json_validator.depth',
        match: 'depth $depth exceeds $maxDepth',
      ));
      return;
    }
    if (value is Map) {
      if (value.length > maxKeyCount) {
        findings.add(Finding(
          type: 'json_validator.key_count',
          match: '${value.length} keys exceeds $maxKeyCount',
        ));
      }
      for (final v in value.values) {
        _walk(v, depth + 1, findings);
      }
    } else if (value is List) {
      if (value.length > maxArrayLength) {
        findings.add(Finding(
          type: 'json_validator.array_length',
          match: '${value.length} elements exceeds $maxArrayLength',
        ));
      }
      for (final v in value) {
        _walk(v, depth + 1, findings);
      }
    }
  }

  ScanResult _result(String text, List<Finding> findings, String reason) {
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }
}
