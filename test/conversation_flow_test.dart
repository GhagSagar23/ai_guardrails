import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

class _PassScanner extends Scanner {
  @override
  String get name => 'passer';
  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.pass(name, text);
}

class _BlockScanner extends Scanner {
  @override
  String get name => 'blocker';
  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.block(name, text,
          findings: [const Finding(type: 'blocker.test')],
          reason: 'test block');
}

ConversationFlow _supportFlow() => ConversationFlow(
      name: 'support',
      initialState: 'greeting',
      canonicalForms: [
        CanonicalForm(
            intent: 'ask_billing', keywords: {'bill', 'invoice', 'payment'}),
        CanonicalForm(
            intent: 'ask_support', keywords: {'help', 'issue', 'problem'}),
        CanonicalForm(intent: 'goodbye', keywords: {'bye', 'thanks', 'done'}),
      ],
      states: {
        'greeting': FlowState(
          name: 'greeting',
          transitions: [
            const FlowTransition(intent: 'ask_billing', targetState: 'billing'),
            const FlowTransition(intent: 'ask_support', targetState: 'support'),
          ],
        ),
        'billing': FlowState(
          name: 'billing',
          allowedTopics: {'billing', 'payment', 'invoice', 'charge'},
          transitions: [
            const FlowTransition(intent: 'ask_support', targetState: 'support'),
            const FlowTransition(intent: 'goodbye', targetState: 'farewell'),
          ],
        ),
        'support': FlowState(
          name: 'support',
          allowedTopics: {'help', 'issue', 'problem', 'troubleshoot'},
          transitions: [
            const FlowTransition(intent: 'ask_billing', targetState: 'billing'),
            const FlowTransition(intent: 'goodbye', targetState: 'farewell'),
          ],
        ),
        'farewell': FlowState(name: 'farewell', terminal: true),
      },
    );

Future<String> _echo(String input) async => 'echo: $input';

void main() {
  group('FlowState', () {
    test('matchesTopic returns true when allowedTopics is empty', () {
      final state = FlowState(name: 'open');
      expect(state.matchesTopic('anything at all'), true);
    });

    test('matchesTopic matches keyword boundary', () {
      final state =
          FlowState(name: 'billing', allowedTopics: {'billing', 'payment'});
      expect(state.matchesTopic('I have a billing question'), true);
      expect(state.matchesTopic('What about my payment?'), true);
      expect(state.matchesTopic('Tell me a joke'), false);
    });

    test('matchesTopic is case-insensitive', () {
      final state = FlowState(name: 's', allowedTopics: {'billing'});
      expect(state.matchesTopic('BILLING issue'), true);
    });

    test('targetFor returns target state for known intent', () {
      final state = FlowState(
        name: 's',
        transitions: [
          const FlowTransition(intent: 'go', targetState: 'next'),
        ],
      );
      expect(state.targetFor('go'), 'next');
      expect(state.targetFor('unknown'), null);
    });

    test('fromJson round-trips through toJson', () {
      final state = FlowState(
        name: 'test',
        allowedTopics: {'a', 'b'},
        transitions: [
          const FlowTransition(intent: 'x', targetState: 'y'),
        ],
        terminal: true,
      );
      final json = state.toJson();
      final restored = FlowState.fromJson('test', json);
      expect(restored.allowedTopics, state.allowedTopics);
      expect(restored.transitions.length, 1);
      expect(restored.terminal, true);
    });
  });

  group('CanonicalForm', () {
    test('matchesKeywords with word boundary', () {
      final form =
          CanonicalForm(intent: 'billing', keywords: {'bill', 'invoice'});
      expect(form.matchesKeywords('I need my bill'), true);
      expect(form.matchesKeywords('Send the invoice'), true);
      expect(form.matchesKeywords('Hello there'), false);
    });

    test('matchesKeywords is case-insensitive', () {
      final form = CanonicalForm(intent: 'x', keywords: {'help'});
      expect(form.matchesKeywords('I need HELP'), true);
    });

    test('fromJson round-trips through toJson', () {
      final form = CanonicalForm(
        intent: 'test',
        keywords: {'a', 'b'},
        description: 'Test intent',
      );
      final restored = CanonicalForm.fromJson(form.toJson());
      expect(restored.intent, 'test');
      expect(restored.keywords, {'a', 'b'});
      expect(restored.description, 'Test intent');
    });
  });

  group('ConversationFlow', () {
    test('throws on invalid initial state', () {
      expect(
        () => ConversationFlow(
          name: 'bad',
          states: {'a': FlowState(name: 'a')},
          initialState: 'missing',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('classifyIntent matches first form', () {
      final flow = _supportFlow();
      expect(flow.classifyIntent('I need help with my bill'), 'ask_billing');
      expect(flow.classifyIntent('I have a problem'), 'ask_support');
      expect(flow.classifyIntent('random text'), null);
    });

    test('classifyIntentWithLlm delegates to callback', () async {
      final flow = _supportFlow();
      final intent = await flow.classifyIntentWithLlm(
        'payment question',
        (prompt) async => 'ask_billing',
      );
      expect(intent, 'ask_billing');
    });

    test('classifyIntentWithLlm returns null for "none"', () async {
      final flow = _supportFlow();
      final intent = await flow.classifyIntentWithLlm(
        'random',
        (prompt) async => 'none',
      );
      expect(intent, null);
    });

    test('classifyIntentWithLlm returns null for unknown intent', () async {
      final flow = _supportFlow();
      final intent = await flow.classifyIntentWithLlm(
        'test',
        (prompt) async => 'totally_unknown',
      );
      expect(intent, null);
    });

    test('classifyIntentWithLlm returns null when no forms', () async {
      final flow = ConversationFlow(
        name: 'empty',
        states: {'s': FlowState(name: 's')},
        initialState: 's',
      );
      final intent = await flow.classifyIntentWithLlm(
        'test',
        (prompt) async => throw StateError('should not be called'),
      );
      expect(intent, null);
    });

    test('fromJson round-trips through toJson', () {
      final flow = _supportFlow();
      final restored = ConversationFlow.fromJson(flow.toJson());
      expect(restored.name, 'support');
      expect(restored.initialState, 'greeting');
      expect(restored.states.length, 4);
      expect(restored.canonicalForms.length, 3);
    });
  });

  group('FlowGuardSession', () {
    late ConversationFlow flow;

    setUp(() {
      flow = _supportFlow();
    });

    test('starts in initial state', () {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard()),
        flow: flow,
      );
      expect(fgs.currentState, 'greeting');
      expect(fgs.stateHistory, ['greeting']);
      expect(fgs.isTerminal, false);
    });

    test('transitions on intent match', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      final outcome =
          await fgs.run(input: 'I need my bill please', llmCall: _echo);
      expect(outcome.blocked, false);
      expect(fgs.currentState, 'billing');
      expect(fgs.stateHistory, ['greeting', 'billing']);
    });

    test('stays in state when on-topic with no transition', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      await fgs.run(input: 'bill question', llmCall: _echo);
      expect(fgs.currentState, 'billing');

      final outcome =
          await fgs.run(input: 'another payment question', llmCall: _echo);
      expect(outcome.blocked, false);
      expect(fgs.currentState, 'billing');
    });

    test('blocks off-topic input in constrained state', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      await fgs.run(input: 'bill question', llmCall: _echo);
      expect(fgs.currentState, 'billing');

      final outcome = await fgs.run(input: 'tell me a joke', llmCall: _echo);
      expect(outcome.blocked, true);
      expect(outcome.blockReason, contains('Off-topic'));
      expect(fgs.currentState, 'billing');
    });

    test('blocks after reaching terminal state', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      await fgs.run(input: 'bill question', llmCall: _echo);
      await fgs.run(input: 'bye now', llmCall: _echo);
      expect(fgs.currentState, 'farewell');
      expect(fgs.isTerminal, true);

      final outcome = await fgs.run(input: 'anything', llmCall: _echo);
      expect(outcome.blocked, true);
      expect(outcome.blockReason, contains('ended'));
    });

    test('does not transition when scanner blocks', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_BlockScanner()])),
        flow: flow,
      );
      final outcome = await fgs.run(input: 'bill question', llmCall: _echo);
      expect(outcome.blocked, true);
      expect(fgs.currentState, 'greeting');
    });

    test('explicit targetState skips intent classification', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      final outcome = await fgs.run(
        input: 'random text',
        llmCall: _echo,
        targetState: 'support',
      );
      expect(outcome.blocked, false);
      expect(fgs.currentState, 'support');
    });

    test('explicit targetState with unknown state blocks', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard()),
        flow: flow,
      );
      final outcome = await fgs.run(
        input: 'test',
        llmCall: _echo,
        targetState: 'nonexistent',
      );
      expect(outcome.blocked, true);
      expect(outcome.blockReason, contains('Unknown flow state'));
    });

    test('transitionTo manually moves state', () {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard()),
        flow: flow,
      );
      expect(fgs.transitionTo('billing'), true);
      expect(fgs.currentState, 'billing');
      expect(fgs.stateHistory, ['greeting', 'billing']);
    });

    test('transitionTo returns false for unknown state', () {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard()),
        flow: flow,
      );
      expect(fgs.transitionTo('nonexistent'), false);
      expect(fgs.currentState, 'greeting');
    });

    test('reset restores initial state', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      await fgs.run(input: 'bill', llmCall: _echo);
      expect(fgs.currentState, 'billing');

      fgs.reset();
      expect(fgs.currentState, 'greeting');
      expect(fgs.stateHistory, ['greeting']);
      expect(fgs.turnCount, 0);
    });

    test('toJson and restore round-trip', () async {
      final guard = AiGuard(inputScanners: [_PassScanner()]);
      final fgs = FlowGuardSession(
        session: GuardSession(guard: guard),
        flow: flow,
      );
      await fgs.run(input: 'bill question', llmCall: _echo);
      await fgs.run(input: 'payment details', llmCall: _echo);

      final json = fgs.toJson();
      final restored = FlowGuardSession.restore(
        session: GuardSession.restore(
          guard: guard,
          state: json['session'] as Map<String, dynamic>,
        ),
        flow: flow,
        state: json,
      );

      expect(restored.currentState, 'billing');
      expect(restored.stateHistory, ['greeting', 'billing']);
    });

    test('allows any topic in unconstrained state', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      final outcome =
          await fgs.run(input: 'literally anything', llmCall: _echo);
      expect(outcome.blocked, false);
      expect(fgs.currentState, 'greeting');
    });

    test('multi-hop transition across states', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
      );
      await fgs.run(input: 'bill question', llmCall: _echo);
      expect(fgs.currentState, 'billing');

      await fgs.run(input: 'I have a problem', llmCall: _echo);
      expect(fgs.currentState, 'support');

      await fgs.run(input: 'bye', llmCall: _echo);
      expect(fgs.currentState, 'farewell');
      expect(fgs.isTerminal, true);

      expect(fgs.stateHistory, ['greeting', 'billing', 'support', 'farewell']);
    });

    test('LLM callback used for intent and topic classification', () async {
      final calls = <String>[];
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
        llmCallback: (prompt) async {
          calls.add(prompt);
          if (prompt.contains('Classify this user message')) {
            return 'none';
          }
          return 'no';
        },
      );
      fgs.transitionTo('billing');

      final outcome =
          await fgs.run(input: 'random unrelated text', llmCall: _echo);
      expect(outcome.blocked, true);
      expect(calls, hasLength(2));
    });

    test('LLM topic check passes when LLM says yes', () async {
      final fgs = FlowGuardSession(
        session: GuardSession(guard: AiGuard(inputScanners: [_PassScanner()])),
        flow: flow,
        llmCallback: (prompt) async {
          if (prompt.contains('Classify this user message')) return 'none';
          return 'yes';
        },
      );
      fgs.transitionTo('billing');

      final outcome =
          await fgs.run(input: 'unrecognized but valid', llmCall: _echo);
      expect(outcome.blocked, false);
    });

    test('delegates turnCount and escalationLevel to session', () {
      final fgs = FlowGuardSession(
        session: GuardSession(
          guard: AiGuard(),
          escalationPolicy:
              const EscalationPolicy(blockThreshold: 2, terminateThreshold: 4),
        ),
        flow: flow,
      );
      expect(fgs.turnCount, 0);
      expect(fgs.escalationLevel, EscalationLevel.warn);
    });
  });
}
