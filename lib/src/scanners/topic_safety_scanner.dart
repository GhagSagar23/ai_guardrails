import '../scanner.dart';

/// LLM-judged topic adherence scanner.
///
/// Prompts the caller's LLM to judge whether text stays within declared
/// topic bounds. Supports allow-lists, deny-lists, or both.
///
/// At least one of [allowedTopics] or [forbiddenTopics] must be non-empty.
class TopicSafetyScanner extends AsyncScanner with LlmDependent {
  final List<String> allowedTopics;
  final List<String> forbiddenTopics;
  final GuardAction action;

  TopicSafetyScanner({
    this.allowedTopics = const [],
    this.forbiddenTopics = const [],
    this.action = GuardAction.block,
  }) : assert(allowedTopics.isNotEmpty || forbiddenTopics.isNotEmpty,
            'Provide at least one of allowedTopics or forbiddenTopics');

  @override
  String get name => 'topic_safety';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    if (text.trim().isEmpty) return ScanResult.pass(name, text);

    final prompt = StringBuffer()
      ..writeln('You are a topic adherence checker.')
      ..writeln();

    if (allowedTopics.isNotEmpty) {
      prompt.writeln('Allowed topics: ${allowedTopics.join(', ')}');
    }
    if (forbiddenTopics.isNotEmpty) {
      prompt.writeln('Forbidden topics: ${forbiddenTopics.join(', ')}');
    }

    prompt
      ..writeln()
      ..writeln('Text:')
      ..writeln(text)
      ..writeln()
      ..writeln('Does the text stay within the allowed topics and avoid '
          'forbidden topics?')
      ..writeln()
      ..writeln('Respond with exactly one word on the first line:')
      ..writeln('ON_TOPIC — the text adheres to topic boundaries')
      ..writeln('OFF_TOPIC — the text strays from allowed topics or '
          'touches forbidden topics')
      ..writeln()
      ..writeln(
          'If OFF_TOPIC, on the next line state which topic was violated.');

    final verdict = await llmCallback(prompt.toString());
    final firstLine = verdict.trim().split('\n').first.trim().toUpperCase();

    if (firstLine.startsWith('ON_TOPIC')) {
      return ScanResult.pass(name, text);
    }

    final violatedTopic = _parseViolation(verdict);
    final isForbidden = forbiddenTopics.any(
        (t) => violatedTopic?.toLowerCase().contains(t.toLowerCase()) ?? false);

    final type =
        isForbidden ? 'topic_safety.forbidden_topic' : 'topic_safety.off_topic';
    final reason = violatedTopic != null
        ? 'Topic violation: $violatedTopic'
        : 'Text is off-topic';

    final findings = [Finding(type: type, match: violatedTopic)];

    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }

  static String? _parseViolation(String verdict) {
    final lines = verdict.trim().split('\n');
    if (lines.length < 2) return null;
    return lines[1].trim();
  }
}
