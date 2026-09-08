import '../scanner.dart';

/// Validates that output is exactly one of a set of allowed values.
///
/// Useful for classification tasks where the LLM must output one of N labels.
class ChoicesValidator implements Scanner {
  final Set<String> choices;
  final bool caseSensitive;
  final bool trim;
  final GuardAction action;

  ChoicesValidator(
    Iterable<String> choices, {
    this.caseSensitive = false,
    this.trim = true,
    this.action = GuardAction.block,
  }) : choices = caseSensitive
            ? choices.toSet()
            : choices.map((c) => c.toLowerCase()).toSet();

  @override
  String get name => 'choices_validator';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    var value = text;
    if (trim) value = value.trim();
    if (!caseSensitive) value = value.toLowerCase();

    if (choices.contains(value)) return ScanResult.pass(name, text);

    final finding = Finding(
      type: 'choices_validator.invalid',
      match: text.length > 50 ? '${text.substring(0, 50)}...' : text,
    );
    final reason = 'output not in allowed choices';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: [finding], reason: reason);
    }
    return ScanResult.block(name, text, findings: [finding], reason: reason);
  }
}
