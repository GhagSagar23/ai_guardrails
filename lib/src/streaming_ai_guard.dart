import 'dart:async';

import 'ai_guard.dart';
import 'scanner.dart';

/// A single scanned segment from a streaming LLM response.
class GuardedChunk {
  /// The segment text, with PII rehydrated if applicable.
  final String text;

  /// `true` when this segment triggered a block — no further chunks will follow.
  final bool blocked;

  /// Why it was blocked.
  final String? blockReason;

  /// Findings from scanning this segment.
  final List<Finding> findings;

  const GuardedChunk({
    required this.text,
    this.blocked = false,
    this.blockReason,
    this.findings = const [],
  });
}

/// Streaming wrapper around [AiGuard] for chunked LLM responses.
///
/// Buffers incoming chunks, splits at [boundary], runs output scanners on
/// each complete segment, and yields [GuardedChunk]s. If a scanner blocks,
/// the stream terminates. Input scanning is identical to [AiGuard].
///
/// Scanners see each segment independently — cross-segment patterns are
/// not detected. Use [AiGuard] for full-output scanning after the stream
/// completes when you need cross-segment coverage (e.g. [SchemaValidator]).
class StreamingAiGuard {
  final AiGuard _guard;

  /// Pattern at which to split buffered text into scannable segments.
  /// Default: newline. Use `RegExp(r'(?<=[.!?])\s')` for sentence boundaries.
  final Pattern boundary;

  StreamingAiGuard({
    List<Scanner> inputScanners = const [],
    List<Scanner> outputScanners = const [],
    bool failClosed = true,
    this.boundary = '\n',
  }) : _guard = AiGuard(
          inputScanners: inputScanners,
          outputScanners: outputScanners,
          failClosed: failClosed,
        );

  /// Scan input only, same as [AiGuard.scanInput].
  List<ScanResult> scanInput(String text) => _guard.scanInput(text);

  /// Guarded streaming round-trip.
  ///
  /// 1. Runs input scanners synchronously — yields a blocked chunk and stops
  ///    if any scanner blocks.
  /// 2. Calls [llmStream] with the sanitized input.
  /// 3. Buffers chunks, splits at [boundary], scans each segment.
  /// 4. Yields [GuardedChunk] per segment. On block, yields the blocked chunk
  ///    and closes — no further chunks follow.
  /// 5. Rehydrates PII placeholders in each segment using the input redaction map.
  Stream<GuardedChunk> run({
    required String input,
    required Stream<String> Function(String sanitizedInput) llmStream,
  }) async* {
    final inRun = _guard.runInputStage(input);
    if (inRun.blocker != null) {
      yield GuardedChunk(
        text: '',
        blocked: true,
        blockReason: inRun.blocker!.reason,
        findings: inRun.results.expand((r) => r.findings).toList(),
      );
      return;
    }

    final piiMap = inRun.redactionMap;
    final buffer = StringBuffer();

    await for (final chunk in llmStream(inRun.text)) {
      buffer.write(chunk);
      final content = buffer.toString();

      // Split at boundary, yielding complete segments.
      final searchFrom = 0;
      while (true) {
        final match = boundary.matchAsPrefix(content, searchFrom) ??
            _findMatch(content, searchFrom);
        if (match == null) break;

        final segment = content.substring(0, match.end);
        final result = _scanAndRehydrate(segment, piiMap);
        if (result.blocked) {
          yield result;
          return;
        }
        yield result;

        // Keep remainder in buffer.
        final remainder = content.substring(match.end);
        buffer
          ..clear()
          ..write(remainder);
        break;
      }
    }

    // Flush remaining buffer.
    final remaining = buffer.toString();
    if (remaining.isNotEmpty) {
      final result = _scanAndRehydrate(remaining, piiMap);
      yield result;
    }
  }

  Match? _findMatch(String content, int start) {
    if (boundary is String) {
      final idx = content.indexOf(boundary as String, start);
      if (idx < 0) return null;
      final end = idx + (boundary as String).length;
      return _SimpleMatch(idx, end, content);
    }
    final regex = boundary as RegExp;
    final matches = regex.allMatches(content, start);
    return matches.isEmpty ? null : matches.first;
  }

  GuardedChunk _scanAndRehydrate(
      String segment, Map<String, String> piiMap) {
    final outRun = _guard.runOutputStage(segment);

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
}

class _SimpleMatch implements Match {
  @override
  final int start;
  @override
  final int end;
  @override
  final String input;
  _SimpleMatch(this.start, this.end, this.input);

  @override
  String? group(int group) => group == 0 ? input.substring(start, end) : null;
  @override
  String operator [](int group) => this.group(group)!;
  @override
  List<String?> groups(List<int> groupIndices) =>
      groupIndices.map(group).toList();
  @override
  int get groupCount => 0;
  @override
  Pattern get pattern => input.substring(start, end);
}
