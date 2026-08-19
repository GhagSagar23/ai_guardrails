import 'dart:convert';

import 'scanner.dart';

/// Structured audit record of a guarded scan. JSON-serializable.
///
/// Contains scanner chain results, findings, and text hashes (never raw text)
/// for compliance-safe logging. Wire to any logging backend via
/// [AiGuard.onScan].
class GuardLog {
  /// Monotonic timestamp (microseconds since epoch).
  final int timestampUs;

  /// Whether the request was blocked.
  final bool blocked;

  /// Stage that blocked, if any.
  final ScanStage? blockedStage;

  /// Blocking reason, if any.
  final String? blockReason;

  /// FNV-1a hash of the original input text (not the text itself).
  final int inputHash;

  /// FNV-1a hash of the final output text, or 0 if blocked before output.
  final int outputHash;

  /// Per-scanner summary: name, passed, score, finding count, finding types.
  final List<ScannerLogEntry> scanners;

  /// Total findings across all scanners.
  final int totalFindings;

  const GuardLog({
    required this.timestampUs,
    required this.blocked,
    this.blockedStage,
    this.blockReason,
    required this.inputHash,
    this.outputHash = 0,
    required this.scanners,
    required this.totalFindings,
  });

  /// Build from a completed [run] outcome.
  factory GuardLog.fromOutcome({
    required bool blocked,
    ScanStage? blockedStage,
    String? blockReason,
    required String inputText,
    String? outputText,
    required List<ScanResult> inputResults,
    required List<ScanResult> outputResults,
  }) {
    final entries = <ScannerLogEntry>[
      for (final r in inputResults)
        ScannerLogEntry(
          name: r.scanner,
          stage: ScanStage.input,
          passed: r.passed,
          score: r.score,
          findingCount: r.findings.length,
          findingTypes: r.findings.map((f) => f.type).toSet().toList()..sort(),
        ),
      for (final r in outputResults)
        ScannerLogEntry(
          name: r.scanner,
          stage: ScanStage.output,
          passed: r.passed,
          score: r.score,
          findingCount: r.findings.length,
          findingTypes: r.findings.map((f) => f.type).toSet().toList()..sort(),
        ),
    ];

    final totalFindings = entries.fold<int>(0, (s, e) => s + e.findingCount);

    return GuardLog(
      timestampUs: DateTime.now().microsecondsSinceEpoch,
      blocked: blocked,
      blockedStage: blockedStage,
      blockReason: blockReason,
      inputHash: _fnv1a(inputText),
      outputHash: outputText != null ? _fnv1a(outputText) : 0,
      scanners: entries,
      totalFindings: totalFindings,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp_us': timestampUs,
        'blocked': blocked,
        if (blockedStage != null) 'blocked_stage': blockedStage!.name,
        if (blockReason != null) 'block_reason': blockReason,
        'input_hash': inputHash,
        'output_hash': outputHash,
        'scanners': scanners.map((e) => e.toJson()).toList(),
        'total_findings': totalFindings,
      };

  String toJsonString() => jsonEncode(toJson());

  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// Per-scanner audit entry within a [GuardLog].
class ScannerLogEntry {
  final String name;
  final ScanStage stage;
  final bool passed;
  final double score;
  final int findingCount;
  final List<String> findingTypes;

  const ScannerLogEntry({
    required this.name,
    required this.stage,
    required this.passed,
    required this.score,
    required this.findingCount,
    this.findingTypes = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'stage': stage.name,
        'passed': passed,
        'score': score,
        'finding_count': findingCount,
        if (findingTypes.isNotEmpty) 'finding_types': findingTypes,
      };
}
