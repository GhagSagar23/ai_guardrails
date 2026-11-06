import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:langchain_core/tools.dart';

/// A LangChain [StringTool] that exposes [AiGuard] scanning to agents.
///
/// Agents invoke this tool to validate content on demand.
/// Returns a JSON string with scan results the agent can reason about.
///
/// ```dart
/// final tool = GuardrailsTool(guard: myGuard);
/// final result = await tool.invoke('Check this text for PII');
/// ```
base class GuardrailsTool extends StringTool<ToolOptions> {
  /// The [AiGuard] pipeline to run.
  final AiGuard guard;

  /// Which stage to scan as — affects which scanners run.
  final ScanStage scanStage;

  /// Creates a [GuardrailsTool].
  GuardrailsTool({
    required this.guard,
    this.scanStage = ScanStage.input,
    super.name = 'guardrails_scan',
    super.description = 'Scan text for safety issues: PII, prompt injection, '
        'secrets, toxicity, and other policy violations. '
        'Returns JSON with pass/block status and findings.',
    super.returnDirect,
    super.handleToolError,
  }) : super(
          inputDescription: 'The text to scan for safety issues',
        );

  @override
  Future<String> invokeInternal(
    String toolInput, {
    ToolOptions? options,
  }) async {
    final stageRun = scanStage == ScanStage.input
        ? await guard.runInputStage(toolInput)
        : await guard.runOutputStage(toolInput);

    final blocked = stageRun.blocker != null;
    final findings = <Map<String, dynamic>>[];

    for (final result in stageRun.results) {
      for (final finding in result.findings) {
        findings.add({
          'scanner': result.scanner,
          'type': finding.type,
          'match': finding.match,
          'start': finding.start,
          'end': finding.end,
        });
      }
    }

    return jsonEncode({
      'blocked': blocked,
      'block_reason': stageRun.blocker?.reason,
      'scanner_count': stageRun.results.length,
      'finding_count': findings.length,
      'findings': findings,
    });
  }
}
