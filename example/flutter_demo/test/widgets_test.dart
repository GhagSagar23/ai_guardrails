import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:flutter_demo/widgets/message_bubble.dart';
import 'package:flutter_demo/widgets/guard_findings_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MessageBubble', () {
    testWidgets('user message aligned right', (tester) async {
      await tester.pumpWidget(_wrap(
        const MessageBubble(text: 'Hello', isUser: true),
      ));
      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('assistant message aligned left', (tester) async {
      await tester.pumpWidget(_wrap(
        const MessageBubble(text: 'Hi there', isUser: false),
      ));
      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('blocked outcome shows warning icon', (tester) async {
      final outcome = GuardOutcome(
        blocked: true,
        blockReason: 'injection detected',
        inputResults: [
          ScanResult.block('prompt_injection', 'bad',
              findings: [const Finding(type: 'injection.override')],
              reason: 'injection detected'),
        ],
        outputResults: [],
      );
      await tester.pumpWidget(_wrap(
        MessageBubble(text: 'Blocked', isUser: false, outcome: outcome),
      ));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('PII findings show redacted chip', (tester) async {
      final outcome = GuardOutcome(
        blocked: false,
        input: '[EMAIL_1]',
        output: 'response',
        piiMap: {'[EMAIL_1]': 'test@test.com'},
        inputResults: [
          ScanResult.warn('pii', '[EMAIL_1]',
              findings: [const Finding(type: 'pii.email')]),
        ],
        outputResults: [],
      );
      await tester.pumpWidget(_wrap(
        MessageBubble(text: 'message', isUser: true, outcome: outcome),
      ));
      expect(find.text('PII redacted'), findsOneWidget);
    });
  });

  group('GuardFindingsCard', () {
    testWidgets('hidden when no findings', (tester) async {
      await tester.pumpWidget(_wrap(
        const GuardFindingsCard(results: []),
      ));
      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('shows count when findings exist', (tester) async {
      await tester.pumpWidget(_wrap(
        GuardFindingsCard(results: [
          ScanResult.warn('reading_level', 'text',
              findings: [
                const Finding(type: 'reading_level.too_complex'),
              ],
              reason: 'grade 15 > 12'),
        ]),
      ));
      expect(find.textContaining('1 finding'), findsOneWidget);
      expect(find.byIcon(Icons.shield), findsOneWidget);
    });

    testWidgets('shows localized message for non-en locale', (tester) async {
      await tester.pumpWidget(_wrap(
        GuardFindingsCard(
          locale: 'ja',
          results: [
            ScanResult.warn('pii', 'text',
                findings: [const Finding(type: 'pii.email')],
                reason: 'email detected'),
          ],
        ),
      ));
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      // Japanese message for PII should appear.
      expect(find.textContaining('個人情報'), findsOneWidget);
    });

    testWidgets('shows multiple scanners', (tester) async {
      await tester.pumpWidget(_wrap(
        GuardFindingsCard(results: [
          ScanResult.warn('reading_level', 'text',
              findings: [
                const Finding(type: 'reading_level.too_complex'),
              ],
              reason: 'too complex'),
          ScanResult.warn('competitor_mention', 'text',
              findings: [const Finding(type: 'competitor.Acme')],
              reason: 'competitor mentioned'),
        ]),
      ));
      expect(find.textContaining('2 findings'), findsOneWidget);
    });

    testWidgets('expands to show finding types', (tester) async {
      await tester.pumpWidget(_wrap(
        GuardFindingsCard(results: [
          ScanResult.warn('bias', 'text',
              findings: [
                const Finding(type: 'bias.gender_generalisation'),
              ],
              reason: 'bias detected'),
        ]),
      ));
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('bias.gender_generalisation'), findsOneWidget);
    });
  });
}
