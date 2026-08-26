import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// What happens when a scanner blocks content.
enum OnBlock {
  /// Throw a [GuardBlockedException].
  throwException,

  /// Return a [GuardedResponse] with [GuardedResponse.blocked] == `true`.
  returnResult,
}

/// Wraps a [GenerativeModel] with [AiGuard] input/output scanning.
///
/// Text parts in the prompt are scanned before the model call. The response
/// text is scanned after. Non-text parts (images, function calls) pass through
/// unscanned.
class GuardedGenerativeModel {
  final GenerativeModel _model;
  final AiGuard _guard;
  final OnBlock _onBlock;

  GuardedGenerativeModel({
    required GenerativeModel model,
    required AiGuard guard,
    OnBlock onBlock = OnBlock.throwException,
  })  : _model = model,
        _guard = guard,
        _onBlock = onBlock;

  /// Guarded version of [GenerativeModel.generateContent].
  ///
  /// Extracts text from prompt [Content] parts, runs input scanners, calls the
  /// model (with redacted text if PII scanning is active), runs output scanners,
  /// and rehydrates any PII placeholders in the response.
  Future<GuardedResponse> generateContent(
    Iterable<Content> prompt, {
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
  }) async {
    final inputText = _extractText(prompt);

    final inputRun = await _guard.runInputStage(inputText);
    if (inputRun.blocker != null) {
      return _handleBlock(
        stage: ScanStage.input,
        reason: inputRun.blocker!.reason ?? 'Input blocked',
        inputResults: inputRun.results,
      );
    }

    final callPrompt = inputRun.text != inputText
        ? _rebuildContent(prompt, inputText, inputRun.text)
        : prompt;

    final response = await _model.generateContent(
      callPrompt,
      safetySettings: safetySettings,
      generationConfig: generationConfig,
      tools: tools,
      toolConfig: toolConfig,
    );

    final responseText = response.text ?? '';
    final outputRun = await _guard.runOutputStage(responseText);
    if (outputRun.blocker != null) {
      return _handleBlock(
        stage: ScanStage.output,
        reason: outputRun.blocker!.reason ?? 'Output blocked',
        inputResults: inputRun.results,
        outputResults: outputRun.results,
        response: response,
      );
    }

    var rehydrated = outputRun.text;
    for (final entry in inputRun.redactionMap.entries) {
      rehydrated = rehydrated.replaceAll(entry.key, entry.value);
    }

    return GuardedResponse._(
      blocked: false,
      response: response,
      rehydratedText: rehydrated,
      inputResults: inputRun.results,
      outputResults: outputRun.results,
      redactionMap: inputRun.redactionMap,
    );
  }

  /// Guarded version of [GenerativeModel.generateContentStream].
  ///
  /// Input scanning is identical to [generateContent]. Output chunks are
  /// buffered and scanned at [boundary] splits (default: newline). On block,
  /// the stream terminates (throw or final blocked chunk, per [OnBlock]).
  Stream<GuardedChunk> generateContentStream(
    Iterable<Content> prompt, {
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
    Pattern boundary = '\n',
  }) async* {
    final inputText = _extractText(prompt);
    final inputRun = await _guard.runInputStage(inputText);
    if (inputRun.blocker != null) {
      final reason = inputRun.blocker!.reason ?? 'Input blocked';
      if (_onBlock == OnBlock.throwException) {
        throw GuardBlockedException(stage: ScanStage.input, reason: reason);
      }
      yield GuardedChunk(text: '', blocked: true, blockReason: reason);
      return;
    }

    final callPrompt = inputRun.text != inputText
        ? _rebuildContent(prompt, inputText, inputRun.text)
        : prompt;
    final piiMap = inputRun.redactionMap;

    final stream = _model.generateContentStream(
      callPrompt,
      safetySettings: safetySettings,
      generationConfig: generationConfig,
      tools: tools,
      toolConfig: toolConfig,
    );

    final buffer = StringBuffer();

    await for (final response in stream) {
      final chunk = response.text ?? '';
      if (chunk.isEmpty) continue;
      buffer.write(chunk);

      final content = buffer.toString();
      final idx = _boundaryIndex(content, boundary);
      if (idx < 0) continue;

      final segment = content.substring(0, idx);
      final remainder = content.substring(idx);
      buffer
        ..clear()
        ..write(remainder);

      final result = await _scanSegment(segment, piiMap);
      if (result.blocked) {
        if (_onBlock == OnBlock.throwException) {
          throw GuardBlockedException(
              stage: ScanStage.output,
              reason: result.blockReason ?? 'Output blocked');
        }
        yield result;
        return;
      }
      yield result;
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

  /// Pass-through to [GenerativeModel.countTokens].
  Future<CountTokensResponse> countTokens(
    Iterable<Content> contents, {
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
  }) =>
      _model.countTokens(
        contents,
        safetySettings: safetySettings,
        generationConfig: generationConfig,
        tools: tools,
        toolConfig: toolConfig,
      );

  GuardedResponse _handleBlock({
    required ScanStage stage,
    required String reason,
    List<ScanResult> inputResults = const [],
    List<ScanResult> outputResults = const [],
    GenerateContentResponse? response,
  }) {
    if (_onBlock == OnBlock.throwException) {
      throw GuardBlockedException(stage: stage, reason: reason);
    }
    return GuardedResponse._(
      blocked: true,
      blockedStage: stage,
      blockReason: reason,
      response: response,
      inputResults: inputResults,
      outputResults: outputResults,
    );
  }

  Future<GuardedChunk> _scanSegment(
      String segment, Map<String, String> piiMap) async {
    final outRun = await _guard.runOutputStage(segment);
    if (outRun.blocker != null) {
      return GuardedChunk(
        text: segment,
        blocked: true,
        blockReason: outRun.blocker!.reason,
        findings: outRun.results.expand((r) => r.findings).toList(),
      );
    }
    var text = outRun.text;
    for (final entry in piiMap.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return GuardedChunk(
      text: text,
      findings: outRun.results.expand((r) => r.findings).toList(),
    );
  }

  static int _boundaryIndex(String content, Pattern boundary) {
    if (boundary is String) return content.indexOf(boundary);
    final match = (boundary as RegExp).firstMatch(content);
    return match?.end ?? -1;
  }

  static String _extractText(Iterable<Content> contents) {
    final buf = StringBuffer();
    for (final content in contents) {
      for (final part in content.parts) {
        if (part is TextPart) {
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(part.text);
        }
      }
    }
    return buf.toString();
  }

  static Iterable<Content> _rebuildContent(
    Iterable<Content> original,
    String originalText,
    String replacementText,
  ) {
    if (originalText == replacementText) return original;
    final textParts = <String>[];
    for (final content in original) {
      for (final part in content.parts) {
        if (part is TextPart) textParts.add(part.text);
      }
    }
    if (textParts.isEmpty) return original;

    // ponytail: single text part = direct replace, multi = offset-walk
    if (textParts.length == 1) {
      return original.map((c) => Content(
            c.role,
            c.parts
                .map((p) => p is TextPart ? TextPart(replacementText) : p)
                .toList(),
          ));
    }

    var remaining = replacementText;
    var partIndex = 0;
    return original.map((c) => Content(
          c.role,
          c.parts.map((p) {
            if (p is! TextPart) return p;
            final orig = textParts[partIndex++];
            final len = orig.length;
            if (remaining.length >= len) {
              final chunk = remaining.substring(0, len);
              remaining = remaining.length > len + 1
                  ? remaining.substring(len + 1)
                  : '';
              return TextPart(chunk);
            }
            final chunk = remaining;
            remaining = '';
            return TextPart(chunk);
          }).toList(),
        ));
  }
}

/// Result of a guarded [GenerativeModel.generateContent] call.
class GuardedResponse {
  /// Whether a scanner blocked the request or response.
  final bool blocked;

  /// Which stage blocked, if any.
  final ScanStage? blockedStage;

  /// Why it was blocked.
  final String? blockReason;

  /// The original model response. `null` when input was blocked.
  final GenerateContentResponse? response;

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
  /// Returns [rehydratedText] when available, falls back to [response.text].
  String? get text => rehydratedText ?? response?.text;

  const GuardedResponse._({
    required this.blocked,
    this.blockedStage,
    this.blockReason,
    this.response,
    this.rehydratedText,
    this.inputResults = const [],
    this.outputResults = const [],
    this.redactionMap = const {},
  });
}

/// Thrown when a scanner blocks and [OnBlock.throwException] is set.
class GuardBlockedException implements Exception {
  final ScanStage stage;
  final String reason;

  const GuardBlockedException({required this.stage, required this.reason});

  @override
  String toString() => 'GuardBlockedException($stage): $reason';
}
