import '../scanner.dart';

/// Positive topic enforcement — "you may ONLY discuss X, Y, Z."
///
/// Complements [BannedTopicScanner] (negative blocklist) with a positive
/// allowlist. In keyword mode (default), scans for word-boundary matches.
/// In LLM-assisted mode, delegates semantic judgment to [LlmCallback].
class TopicAllowlistScanner extends AsyncScanner with LlmDependent {
  final List<String> allowedTopics;
  final bool useLlm;
  final GuardAction action;

  final List<RegExp> _patterns;

  TopicAllowlistScanner({
    required this.allowedTopics,
    this.useLlm = false,
    this.action = GuardAction.block,
  }) : _patterns = [
          for (final t in allowedTopics)
            RegExp('\\b${RegExp.escape(t)}\\b', caseSensitive: false),
        ];

  @override
  String get name => 'topic_allowlist';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  Future<ScanResult> scanAsync(
    String text, {
    ScanStage stage = ScanStage.input,
  }) async {
    if (allowedTopics.isEmpty) return ScanResult.pass(name, text);

    if (useLlm) return _llmScan(text);
    return _keywordScan(text);
  }

  ScanResult _keywordScan(String text) {
    for (final p in _patterns) {
      if (p.hasMatch(text)) return ScanResult.pass(name, text);
    }
    return _block(text);
  }

  Future<ScanResult> _llmScan(String text) async {
    final prompt = 'Determine if the following text is about one of these '
        'allowed topics: ${allowedTopics.join(', ')}.\n\n'
        'Text: $text\n\n'
        'Reply with ONLY "yes" or "no".';
    final response = (await llmCallback(prompt)).trim().toLowerCase();
    if (response.startsWith('yes')) return ScanResult.pass(name, text);
    return _block(text);
  }

  ScanResult _block(String text) {
    final finding = const Finding(type: 'topic_allowlist.off_topic');
    final reason =
        'text does not match allowed topics: ${allowedTopics.join(', ')}';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: [finding], reason: reason);
    }
    return ScanResult.block(name, text, findings: [finding], reason: reason);
  }
}
