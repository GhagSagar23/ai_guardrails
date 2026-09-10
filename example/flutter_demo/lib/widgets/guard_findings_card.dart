import 'package:flutter/material.dart';
import 'package:ai_guardrails/ai_guardrails.dart';

class GuardFindingsCard extends StatelessWidget {
  final List<ScanResult> results;
  final String locale;
  const GuardFindingsCard({
    super.key,
    required this.results,
    this.locale = 'en',
  });

  @override
  Widget build(BuildContext context) {
    final withFindings = results.where((r) => r.hasFindings).toList();
    if (withFindings.isEmpty) return const SizedBox.shrink();

    final totalFindings =
        withFindings.fold<int>(0, (sum, r) => sum + r.findings.length);
    final allPassed = withFindings.every((r) => r.passed);

    // ponytail: allPassed means warnings only (orange); any failure = red
    final severityColor = allPassed ? Colors.orange : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: Icon(Icons.shield, color: severityColor),
        title: Text(
          'Guard Log ($totalFindings finding${totalFindings == 1 ? '' : 's'})',
        ),
        children: [
          for (final r in withFindings) _resultTile(context, r),
        ],
      ),
    );
  }

  Widget _resultTile(BuildContext context, ScanResult r) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              r.passed ? Icons.check_circle : Icons.cancel,
              color: r.passed ? Colors.green : Colors.red,
            ),
            title: Text(r.scanner),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.reason != null) Text(r.reason!),
                Text(
                  r.userMessage(locale: locale),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                r.score.toStringAsFixed(2),
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          if (r.findings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final f in r.findings)
                    Chip(
                      label: Text(f.type),
                      labelStyle: theme.textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
