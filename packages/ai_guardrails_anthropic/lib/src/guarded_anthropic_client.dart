import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

/// What happens when a scanner blocks content.
enum OnBlock {
  /// Throw a [GuardBlockedException].
  throwException,

  /// Return a [GuardedResponse] with [GuardedResponse.blocked] == `true`.
  returnResult,
}

/// Wraps an [AnthropicClient] with [AiGuard] input/output scanning.
///
/// Text in the request messages is scanned before the API call. The response
/// text is scanned after. Non-text blocks (images, tool use) pass through
/// unscanned.
class GuardedAnthropicClient {
  final AnthropicClient _client;
  final AiGuard _guard;
  final OnBlock _onBlock;

  /// Creates a [GuardedAnthropicClient] wrapping [client] with [guard].
  GuardedAnthropicClient({
    required AnthropicClient client,
    required AiGuard guard,
    OnBlock onBlock = OnBlock.throwException,
  })  : _client = client,
        _guard = guard,
        _onBlock = onBlock;

  /// Guarded version of [AnthropicClient.createMessage].
  ///
  /// Extracts text from the request messages, runs input scanners, calls the
  /// API (with redacted text if PII scanning is active), runs output scanners,
  /// and rehydrates any PII placeholders in the response.
  Future<GuardedResponse> createMessage({
    required CreateMessageRequest request,
  }) async {
    final inputText = _extractInput(request.messages);

    final inputRun = await _guard.runInputStage(inputText);
    if (inputRun.blocker != null) {
      return _handleBlock(
        stage: ScanStage.input,
        reason: inputRun.blocker!.reason ?? 'Input blocked',
        inputResults: inputRun.results,
      );
    }

    final callRequest = inputRun.text != inputText
        ? _rebuildRequest(request, inputRun.text, inputRun.redactionMap)
        : request;

    final message = await _client.createMessage(request: callRequest);

    final responseText = _contentText(message.content, '');
    final outputRun = await _guard.runOutputStage(responseText);
    if (outputRun.blocker != null) {
      return _handleBlock(
        stage: ScanStage.output,
        reason: outputRun.blocker!.reason ?? 'Output blocked',
        inputResults: inputRun.results,
        outputResults: outputRun.results,
        message: message,
      );
    }

    return GuardedResponse._(
      blocked: false,
      message: message,
      rehydratedText: _rehydrate(outputRun.text, inputRun.redactionMap),
      inputResults: inputRun.results,
      outputResults: outputRun.results,
      redactionMap: inputRun.redactionMap,
    );
  }

  /// Guarded version of [AnthropicClient.createMessageStream].
  ///
  /// Input scanning is identical to [createMessage]. Output text deltas are
  /// buffered and scanned at [boundary] splits (default: newline). On block,
  /// the stream terminates (throw or final blocked chunk, per [OnBlock]).
  Stream<GuardedChunk> createMessageStream({
    required CreateMessageRequest request,
    Pattern boundary = '\n',
  }) async* {
    final inputText = _extractInput(request.messages);
    final inputRun = await _guard.runInputStage(inputText);
    if (inputRun.blocker != null) {
      final reason = inputRun.blocker!.reason ?? 'Input blocked';
      if (_onBlock == OnBlock.throwException) {
        throw GuardBlockedException(stage: ScanStage.input, reason: reason);
      }
      yield GuardedChunk(text: '', blocked: true, blockReason: reason);
      return;
    }

    final callRequest = inputRun.text != inputText
        ? _rebuildRequest(request, inputRun.text, inputRun.redactionMap)
        : request;
    final piiMap = inputRun.redactionMap;

    final buffer = StringBuffer();

    await for (final event
        in _client.createMessageStream(request: callRequest)) {
      if (event is! ContentBlockDeltaEvent) continue;
      final delta = event.delta;
      if (delta is! TextBlockDelta || delta.text.isEmpty) continue;
      buffer.write(delta.text);

      final content = buffer.toString();
      final idx = _boundaryIndex(content, boundary);
      if (idx < 0) continue;

      final segment = content.substring(0, idx);
      buffer
        ..clear()
        ..write(content.substring(idx));

      final result = await _scanSegment(segment, piiMap);
      if (result.blocked && _onBlock == OnBlock.throwException) {
        throw GuardBlockedException(
            stage: ScanStage.output,
            reason: result.blockReason ?? 'Output blocked');
      }
      yield result;
      if (result.blocked) return;
    }

    final remaining = buffer.toString();
    if (remaining.isNotEmpty) {
      final result = await _scanSegment(remaining, piiMap);
      if (result.blocked && _onBlock == OnBlock.throwException) {
        throw GuardBlockedException(
            stage: ScanStage.output,
            reason: result.blockReason ?? 'Output blocked');
      }
      yield result;
    }
  }

  GuardedResponse _handleBlock({
    required ScanStage stage,
    required String reason,
    List<ScanResult> inputResults = const [],
    List<ScanResult> outputResults = const [],
    Message? message,
  }) {
    if (_onBlock == OnBlock.throwException) {
      throw GuardBlockedException(stage: stage, reason: reason);
    }
    return GuardedResponse._(
      blocked: true,
      blockedStage: stage,
      blockReason: reason,
      message: message,
      inputResults: inputResults,
      outputResults: outputResults,
    );
  }

  Future<GuardedChunk> _scanSegment(
      String segment, Map<String, String> piiMap) async {
    final outRun = await _guard.runOutputStage(segment);
    final findings = outRun.results.expand((r) => r.findings).toList();
    if (outRun.blocker != null) {
      return GuardedChunk(
        text: '', // never surface blocked content
        blocked: true,
        blockReason: outRun.blocker!.reason,
        findings: findings,
      );
    }
    return GuardedChunk(
      text: _rehydrate(outRun.text, piiMap),
      findings: findings,
    );
  }

  static String _rehydrate(String text, Map<String, String> piiMap) {
    for (final entry in piiMap.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }

  static int _boundaryIndex(String content, Pattern boundary) {
    if (boundary is String) {
      final i = content.indexOf(boundary);
      return i < 0 ? -1 : i + boundary.length;
    }
    final match = (boundary as RegExp).firstMatch(content);
    return match?.end ?? -1;
  }

  static List<String> _texts(Iterable<Message> messages) => [
        for (final m in messages)
          switch (m.content) {
            MessageContentText(:final value) => value,
            MessageContentBlocks(:final value) => [
                for (final b in value)
                  if (b is TextBlock) b.text
              ].join('\n'),
          }
      ].where((t) => t.isNotEmpty).toList();

  static String _extractInput(Iterable<Message> messages) =>
      _texts(messages).join('\n');

  static String _contentText(MessageContent content, String separator) =>
      switch (content) {
        MessageContentText(:final value) => value,
        MessageContentBlocks(:final value) => [
            for (final b in value)
              if (b is TextBlock) b.text
          ].join(separator),
      };

  static CreateMessageRequest _rebuildRequest(
    CreateMessageRequest request,
    String replacementText,
    Map<String, String> redactionMap,
  ) {
    // ponytail: only one text segment can take the redacted text directly;
    // with several, swap original values for placeholders per segment (the
    // redaction map is the only per-segment-safe signal). Other text-rewriting
    // scanners are not reflected across multiple segments.
    final single = _texts(request.messages).length == 1;
    String swap(String t) {
      if (single) return replacementText;
      for (final e in redactionMap.entries) {
        t = t.replaceAll(e.value, e.key);
      }
      return t;
    }

    final messages = [
      for (final m in request.messages)
        m.copyWith(
          content: switch (m.content) {
            MessageContentText(:final value) =>
              MessageContent.text(value.isEmpty ? value : swap(value)),
            MessageContentBlocks(:final value) => MessageContent.blocks([
                for (final b in value)
                  b is TextBlock ? Block.text(text: swap(b.text)) : b
              ]),
          },
        ),
    ];
    return request.copyWith(messages: messages);
  }
}

/// Result of a guarded [AnthropicClient.createMessage] call.
class GuardedResponse {
  /// Whether a scanner blocked the request or response.
  final bool blocked;

  /// Which stage blocked, if any.
  final ScanStage? blockedStage;

  /// Why it was blocked.
  final String? blockReason;

  /// The original Anthropic response. `null` when input was blocked.
  final Message? message;

  /// Response text with PII placeholders rehydrated. `null` when blocked.
  final String? rehydratedText;

  /// Per-scanner input results.
  final List<ScanResult> inputResults;

  /// Per-scanner output results.
  final List<ScanResult> outputResults;

  /// PII redaction map from input scanning.
  final Map<String, String> redactionMap;

  /// Every finding across both pipelines.
  List<Finding> get allFindings => [
        for (final r in inputResults) ...r.findings,
        for (final r in outputResults) ...r.findings,
      ];

  /// Shorthand: the final text to show the user.
  /// Returns [rehydratedText] when available, falls back to the raw
  /// [message] text.
  String? get text =>
      rehydratedText ??
      (message == null
          ? null
          : GuardedAnthropicClient._contentText(message!.content, ''));

  const GuardedResponse._({
    required this.blocked,
    this.blockedStage,
    this.blockReason,
    this.message,
    this.rehydratedText,
    this.inputResults = const [],
    this.outputResults = const [],
    this.redactionMap = const {},
  });
}

/// Thrown when a scanner blocks and [OnBlock.throwException] is set.
class GuardBlockedException implements Exception {
  /// The pipeline stage that triggered the block.
  final ScanStage stage;

  /// Human-readable reason the request was blocked.
  final String reason;

  /// Creates a [GuardBlockedException] for the given [stage] and [reason].
  const GuardBlockedException({required this.stage, required this.reason});

  @override
  String toString() => 'GuardBlockedException($stage): $reason';
}
