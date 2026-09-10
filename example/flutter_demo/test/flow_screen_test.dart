import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/screens/flow_screen.dart';
import 'package:flutter_demo/providers/llm_provider.dart';
import 'package:flutter_demo/widgets/message_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('FlowScreen', () {
    testWidgets('renders empty state with hint text', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );
      expect(find.textContaining('Hello!'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows flow state chips', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );
      expect(find.text('greeting'), findsOneWidget);
      expect(find.text('billing'), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      expect(find.text('farewell'), findsOneWidget);
    });

    testWidgets('greeting state selected initially', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );
      final greetingChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'greeting'),
      );
      expect(greetingChip.selected, isTrue);
    });

    testWidgets('sends message and shows response', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      await tester.enterText(find.byType(TextField), 'Hello!');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.byType(MessageBubble), findsWidgets);
      expect(find.textContaining('Hello!'), findsOneWidget);
    });

    testWidgets('billing intent triggers state transition', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      await tester.enterText(
        find.byType(TextField),
        'I need help with my bill',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      final billingChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'billing'),
      );
      expect(billingChip.selected, isTrue);
      expect(find.textContaining('greeting → billing'), findsWidgets);
    });

    testWidgets('off-topic blocked in billing state', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      // Transition to billing first.
      await tester.enterText(
        find.byType(TextField),
        'I need help with billing',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Now send off-topic message.
      await tester.enterText(
        find.byType(TextField),
        'what is the weather today',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('Off-topic'), findsOneWidget);
    });

    testWidgets('farewell transition reaches terminal state', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      // Transition to billing.
      await tester.enterText(
        find.byType(TextField),
        'I need to check my invoice',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Transition to farewell.
      await tester.enterText(find.byType(TextField), 'thanks bye');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      final farewellChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'farewell'),
      );
      expect(farewellChip.selected, isTrue);

      // Input disabled.
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.enabled, isFalse);
    });

    testWidgets('reset restores greeting state', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      // Transition to billing.
      await tester.enterText(
        find.byType(TextField),
        'what is the price',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Verify billing.
      var billingChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'billing'),
      );
      expect(billingChip.selected, isTrue);

      // Reset.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      final greetingChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'greeting'),
      );
      expect(greetingChip.selected, isTrue);
      expect(find.byType(MessageBubble), findsNothing);
    });

    testWidgets('state history shows path', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      await tester.enterText(
        find.byType(TextField),
        'what is the price',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('greeting'), findsWidgets);
      expect(find.textContaining('billing'), findsWidgets);
    });

    testWidgets('empty message does not send', (tester) async {
      await tester.pumpWidget(
        _wrap(FlowScreen(provider: MockFlowLlmProvider())),
      );

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.textContaining('Hello!'), findsOneWidget);
    });
  });
}
