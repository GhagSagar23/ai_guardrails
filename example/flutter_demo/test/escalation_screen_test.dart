import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/screens/escalation_screen.dart';
import 'package:flutter_demo/providers/llm_provider.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('EscalationScreen', () {
    testWidgets('renders empty state with hint text', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );
      expect(find.textContaining('Send PII'), findsOneWidget);
      expect(find.textContaining('Level: WARN'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows turn and finding counters', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );
      expect(find.textContaining('Turn 0'), findsOneWidget);
      expect(find.textContaining('0 findings'), findsOneWidget);
    });

    testWidgets('sending normal text stays at warn', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );

      await tester.enterText(find.byType(TextField), 'Hello there');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('Level: WARN'), findsOneWidget);
      expect(find.textContaining('Turn 1'), findsOneWidget);
    });

    testWidgets('PII input accumulates findings', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );

      await tester.enterText(
        find.byType(TextField),
        'my email is test@example.com',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('PII redacted'), findsWidgets);
      expect(find.textContaining('1 finding'), findsWidgets);
    });

    testWidgets('3 findings escalates to BLOCK', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );

      for (final email in [
        'email me at a@test.com',
        'contact b@test.com please',
        'reach me at c@test.com',
      ]) {
        await tester.enterText(find.byType(TextField), email);
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('Level: BLOCK'), findsOneWidget);
    });

    testWidgets('5 findings escalates to TERMINATE', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );

      for (final email in [
        'email a@test.com',
        'email b@test.com',
        'email c@test.com',
        'email d@test.com',
        'email e@test.com',
      ]) {
        await tester.enterText(find.byType(TextField), email);
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('Level: TERMINATE'), findsOneWidget);
    });

    testWidgets('reset restores warn level', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );

      // Accumulate some findings.
      await tester.enterText(
        find.byType(TextField),
        'email me at a@test.com',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 finding'), findsWidgets);

      // Reset.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(find.textContaining('Level: WARN'), findsOneWidget);
      expect(find.textContaining('Turn 0'), findsOneWidget);
      expect(find.textContaining('0 findings'), findsOneWidget);
    });

    testWidgets('terminated session blocks all turns', (tester) async {
      await tester.pumpWidget(
        _wrap(EscalationScreen(provider: MockLlmProvider())),
      );

      // Escalate to terminate.
      for (final email in [
        'email a@test.com',
        'email b@test.com',
        'email c@test.com',
        'email d@test.com',
        'email e@test.com',
      ]) {
        await tester.enterText(find.byType(TextField), email);
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
      }

      // Send clean message.
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Session terminated'),
        findsWidgets,
      );
    });
  });
}
