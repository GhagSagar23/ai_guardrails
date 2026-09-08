/// Orchestrator-level failure strategies for scanner findings.
///
/// Configured per-scanner via [AiGuard.onFailActions]. Overrides the
/// scanner's own pass/block decision at the pipeline level.
enum OnFailAction {
  /// Halt the pipeline and report as blocked.
  block,

  /// Record findings but continue the pipeline.
  warn,

  /// Remove the flagged content (replace with empty string) and continue.
  filter,

  /// Apply the scanner's [ScanResult.suggestedFix] and continue.
  fix,

  /// Signal to [GuardedLlmCall] to retry with error feedback.
  /// In [AiGuard.run], treated as [block].
  reask,

  /// Stop the pipeline and return an empty response (graceful refusal).
  refrain,

  /// Ignore the scanner's findings entirely — skip the scanner.
  noop,
}

/// Parse an [OnFailAction] from its string name.
OnFailAction? parseOnFailAction(String? s) {
  if (s == null) return null;
  return switch (s) {
    'block' => OnFailAction.block,
    'warn' => OnFailAction.warn,
    'filter' => OnFailAction.filter,
    'fix' => OnFailAction.fix,
    'reask' => OnFailAction.reask,
    'refrain' => OnFailAction.refrain,
    'noop' => OnFailAction.noop,
    _ => throw ArgumentError('Unknown OnFailAction: $s'),
  };
}
