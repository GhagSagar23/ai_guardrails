import 'ai_guard.dart';
import 'guard_session.dart';
import 'scanner.dart';

/// A transition from one flow state to another, triggered by an intent.
class FlowTransition {
  /// The intent name.
  final String intent;

  /// The state to transition to.
  final String targetState;

  /// Creates a [FlowTransition].
  const FlowTransition({required this.intent, required this.targetState});

  /// Creates a [FlowTransition] from JSON.
  factory FlowTransition.fromJson(Map<String, dynamic> json) => FlowTransition(
        intent: json['intent'] as String,
        targetState: json['targetState'] as String,
      );

  /// Serializes this to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'intent': intent,
        'targetState': targetState,
      };
}

/// A state in a [ConversationFlow].
///
/// Each state defines:
/// - [allowedTopics]: keyword set for topic-rail enforcement on
///   non-transition turns. Empty means any topic is allowed.
/// - [transitions]: intent-to-state mappings.
/// - [terminal]: if true, no further turns are processed.
class FlowState {
  /// The name.
  final String name;

  /// Topics that are permitted.
  final Set<String> allowedTopics;

  /// Outgoing transitions.
  final List<FlowTransition> transitions;

  /// Whether this is a terminal state.
  final bool terminal;

  final List<RegExp> _topicPatterns;

  /// Creates a [FlowState].
  FlowState({
    required this.name,
    this.allowedTopics = const {},
    this.transitions = const [],
    this.terminal = false,
  }) : _topicPatterns = [
          for (final t in allowedTopics)
            RegExp('\\b${RegExp.escape(t)}\\b', caseSensitive: false),
        ];

  /// Whether [text] matches this state's allowed topics.
  bool matchesTopic(String text) {
    if (allowedTopics.isEmpty) return true;
    return _topicPatterns.any((p) => p.hasMatch(text));
  }

  /// Returns the target state for [intent], or null.
  String? targetFor(String intent) {
    for (final t in transitions) {
      if (t.intent == intent) return t.targetState;
    }
    return null;
  }

  /// Creates a [FlowState] from JSON.
  factory FlowState.fromJson(String name, Map<String, dynamic> json) =>
      FlowState(
        name: name,
        allowedTopics:
            (json['allowedTopics'] as List?)?.cast<String>().toSet() ??
                const {},
        transitions: (json['transitions'] as List?)
                ?.map((e) => FlowTransition.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        terminal: json['terminal'] as bool? ?? false,
      );

  /// Serializes this to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (allowedTopics.isNotEmpty) 'allowedTopics': allowedTopics.toList(),
        if (transitions.isNotEmpty)
          'transitions': transitions.map((t) => t.toJson()).toList(),
        if (terminal) 'terminal': true,
      };
}

/// Maps user text to a canonical intent via keyword matching.
///
/// In keyword mode, matches when any keyword appears as a whole word
/// (case-insensitive) in the input. When an [LlmCallback] is available
/// on [FlowGuardSession], the [description] is sent to the LLM for
/// semantic classification.
class CanonicalForm {
  /// The intent name.
  final String intent;

  /// Keywords that signal this intent.
  final Set<String> keywords;

  /// Optional human-readable description.
  final String? description;

  final List<RegExp> _patterns;

  /// Creates a [CanonicalForm].
  CanonicalForm({
    required this.intent,
    required this.keywords,
    this.description,
  }) : _patterns = [
          for (final k in keywords)
            RegExp('\\b${RegExp.escape(k)}\\b', caseSensitive: false),
        ];

  /// Whether [text] matches any keyword.
  bool matchesKeywords(String text) => _patterns.any((p) => p.hasMatch(text));

  /// Creates a [CanonicalForm] from JSON.
  factory CanonicalForm.fromJson(Map<String, dynamic> json) => CanonicalForm(
        intent: json['intent'] as String,
        keywords:
            (json['keywords'] as List?)?.cast<String>().toSet() ?? const {},
        description: json['description'] as String?,
      );

  /// Serializes this to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'intent': intent,
        'keywords': keywords.toList(),
        if (description != null) 'description': description,
      };
}

/// A declarative conversation flow — a state machine over allowed topics.
///
/// Define states with topic rails and intent-based transitions, then
/// wrap a [GuardSession] with [FlowGuardSession] to enforce the flow.
///
/// ```dart
/// final flow = ConversationFlow.fromJson({
///   'name': 'support',
///   'initialState': 'greeting',
///   'canonicalForms': [
///     {'intent': 'ask_billing', 'keywords': ['bill', 'invoice', 'payment']},
///     {'intent': 'goodbye', 'keywords': ['bye', 'thanks', 'done']},
///   ],
///   'states': {
///     'greeting': {
///       'transitions': [
///         {'intent': 'ask_billing', 'targetState': 'billing'},
///       ],
///     },
///     'billing': {
///       'allowedTopics': ['billing', 'payment', 'invoice'],
///       'transitions': [
///         {'intent': 'goodbye', 'targetState': 'farewell'},
///       ],
///     },
///     'farewell': {'terminal': true},
///   },
/// });
/// ```
class ConversationFlow {
  /// The name.
  final String name;

  /// States by name.
  final Map<String, FlowState> states;

  /// Name of the starting state.
  final String initialState;

  /// Canonical intents recognised in user messages.
  final List<CanonicalForm> canonicalForms;

  /// Creates a [ConversationFlow].
  ConversationFlow({
    required this.name,
    required this.states,
    required this.initialState,
    this.canonicalForms = const [],
  }) {
    if (!states.containsKey(initialState)) {
      throw ArgumentError('Initial state "$initialState" not found in states');
    }
  }

  /// Classify [text] into an intent using keyword matching.
  String? classifyIntent(String text) {
    for (final form in canonicalForms) {
      if (form.matchesKeywords(text)) return form.intent;
    }
    return null;
  }

  /// Classify [text] into an intent using an LLM.
  Future<String?> classifyIntentWithLlm(
    String text,
    LlmCallback llmCallback,
  ) async {
    if (canonicalForms.isEmpty) return null;
    final formList = canonicalForms
        .map((f) => '- ${f.intent}: ${f.description ?? f.keywords.join(', ')}')
        .join('\n');
    final prompt = 'Given these possible user intents:\n$formList\n\n'
        'Classify this user message: "$text"\n\n'
        'Reply with ONLY the intent name, or "none" if no intent matches.';
    final response = (await llmCallback(prompt)).trim().toLowerCase();
    if (response == 'none') return null;
    for (final form in canonicalForms) {
      if (form.intent.toLowerCase() == response) return form.intent;
    }
    return null;
  }

  /// Creates a [ConversationFlow] from JSON.
  factory ConversationFlow.fromJson(Map<String, dynamic> json) {
    final statesJson = json['states'] as Map<String, dynamic>;
    final states = <String, FlowState>{};
    for (final entry in statesJson.entries) {
      states[entry.key] =
          FlowState.fromJson(entry.key, entry.value as Map<String, dynamic>);
    }
    return ConversationFlow(
      name: json['name'] as String,
      states: states,
      initialState: json['initialState'] as String,
      canonicalForms: (json['canonicalForms'] as List?)
              ?.map((e) => CanonicalForm.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// Serializes this to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'name': name,
        'initialState': initialState,
        'canonicalForms': canonicalForms.map((f) => f.toJson()).toList(),
        'states': {
          for (final entry in states.entries) entry.key: entry.value.toJson(),
        },
      };
}

/// Conversation-level flow enforcement wrapping [GuardSession].
///
/// On each turn:
/// 1. If current state is terminal, block.
/// 2. Classify intent (keyword or LLM).
/// 3. If intent triggers a transition, run scanners and move state on pass.
/// 4. If no transition, enforce current state's topic rail, then run scanners.
class FlowGuardSession {
  /// The underlying guard session.
  final GuardSession session;

  /// The conversation flow definition.
  final ConversationFlow flow;

  /// The LLM callback used by this scanner.
  final LlmCallback? llmCallback;

  String _currentState;
  final _stateHistory = <String>[];

  /// Creates a [FlowGuardSession].
  FlowGuardSession({
    required this.session,
    required this.flow,
    this.llmCallback,
  }) : _currentState = flow.initialState {
    _stateHistory.add(flow.initialState);
  }

  /// The current flow state name.
  String get currentState => _currentState;

  /// States visited so far, in order.
  List<String> get stateHistory => List.unmodifiable(_stateHistory);

  /// Whether the current state is terminal.
  bool get isTerminal => flow.states[_currentState]?.terminal ?? false;

  /// Number of turns processed.
  int get turnCount => session.turnCount;

  /// The current escalation level.
  EscalationLevel get escalationLevel => session.escalationLevel;

  /// Run a turn with flow enforcement.
  ///
  /// When [targetState] is provided, skips intent classification and
  /// transitions directly (useful for system-initiated transitions).
  Future<GuardOutcome> run({
    required String input,
    required Future<String> Function(String) llmCall,
    String? targetState,
  }) async {
    final state = flow.states[_currentState];
    if (state == null || state.terminal) {
      return const GuardOutcome(
        blocked: true,
        blockReason: 'Conversation flow has ended',
      );
    }

    String? nextState = targetState;

    if (nextState == null) {
      final intent = llmCallback != null
          ? await flow.classifyIntentWithLlm(input, llmCallback!)
          : flow.classifyIntent(input);
      if (intent != null) nextState = state.targetFor(intent);
    }

    if (nextState != null) {
      if (!flow.states.containsKey(nextState)) {
        return GuardOutcome(
          blocked: true,
          blockReason: 'Unknown flow state: $nextState',
        );
      }
      final outcome = await session.run(input: input, llmCall: llmCall);
      if (!outcome.blocked) {
        _currentState = nextState;
        _stateHistory.add(nextState);
      }
      return outcome;
    }

    if (!state.matchesTopic(input)) {
      if (llmCallback != null) {
        final onTopic = await _llmTopicCheck(input, state);
        if (!onTopic) return _topicBlockOutcome(state);
      } else {
        return _topicBlockOutcome(state);
      }
    }

    return session.run(input: input, llmCall: llmCall);
  }

  Future<bool> _llmTopicCheck(String text, FlowState state) async {
    final topics = state.allowedTopics.join(', ');
    final prompt = 'Is this text about one of these topics: $topics?\n\n'
        'Text: $text\n\nReply with ONLY "yes" or "no".';
    final response = (await llmCallback!(prompt)).trim().toLowerCase();
    return response.startsWith('yes');
  }

  GuardOutcome _topicBlockOutcome(FlowState state) => GuardOutcome(
        blocked: true,
        blockReason: 'Off-topic for flow state "${state.name}". '
            'Allowed topics: ${state.allowedTopics.join(', ')}',
      );

  /// Manually transition to [state] without running scanners.
  bool transitionTo(String state) {
    if (!flow.states.containsKey(state)) return false;
    _currentState = state;
    _stateHistory.add(state);
    return true;
  }

  /// Resets the session to its initial state.
  void reset() {
    _currentState = flow.initialState;
    _stateHistory.clear();
    _stateHistory.add(flow.initialState);
    session.reset();
  }

  /// Serializes this to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'currentState': _currentState,
        'stateHistory': List<String>.from(_stateHistory),
        'session': session.toJson(),
      };

  /// Restores a [FlowGuardSession] from saved state.
  factory FlowGuardSession.restore({
    required GuardSession session,
    required ConversationFlow flow,
    required Map<String, dynamic> state,
    LlmCallback? llmCallback,
  }) {
    final fgs = FlowGuardSession(
      session: session,
      flow: flow,
      llmCallback: llmCallback,
    );
    fgs._currentState = state['currentState'] as String;
    fgs._stateHistory
      ..clear()
      ..addAll((state['stateHistory'] as List).cast<String>());
    return fgs;
  }
}
