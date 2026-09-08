import '../scanner.dart';

/// Validates that text satisfies numeric bounds and/or string length constraints.
///
/// For numeric mode, parses the text as a number and checks [min]/[max].
/// String length mode checks [minLength]/[maxLength] on the raw text.
/// Both can be combined.
class RangeValidator implements Scanner {
  final double? min;
  final double? max;
  final int? minLength;
  final int? maxLength;
  final GuardAction action;

  RangeValidator({
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.action = GuardAction.block,
  });

  @override
  String get name => 'range_validator';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];

    if (minLength != null && text.length < minLength!) {
      findings.add(Finding(
        type: 'range_validator.min_length',
        match: 'length ${text.length} < $minLength',
      ));
    }
    if (maxLength != null && text.length > maxLength!) {
      findings.add(Finding(
        type: 'range_validator.max_length',
        match: 'length ${text.length} > $maxLength',
      ));
    }

    if (min != null || max != null) {
      final value = num.tryParse(text.trim());
      if (value == null) {
        findings.add(const Finding(type: 'range_validator.not_numeric'));
      } else {
        if (min != null && value < min!) {
          findings.add(Finding(
            type: 'range_validator.min',
            match: '$value < $min',
          ));
        }
        if (max != null && value > max!) {
          findings.add(Finding(
            type: 'range_validator.max',
            match: '$value > $max',
          ));
        }
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final reason = findings.map((f) => f.match ?? f.type).join('; ');
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }
}
