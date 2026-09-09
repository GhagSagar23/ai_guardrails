import 'package:flutter/material.dart';
import 'package:ai_guardrails/ai_guardrails.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final GuardOutcome? outcome;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.outcome,
  });

  bool get _isBlocked => outcome?.blocked ?? false;

  bool get _hasPiiFindings =>
      outcome != null &&
      outcome!.allFindings.any((f) => f.type.startsWith('pii.'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_isBlocked) return _buildBlocked(colors);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isUser ? colors.onPrimary : colors.onSurface,
              ),
            ),
            if (_hasPiiFindings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  label: const Text('PII redacted'),
                  labelStyle: theme.textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlocked(ColorScheme colors) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.error, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
