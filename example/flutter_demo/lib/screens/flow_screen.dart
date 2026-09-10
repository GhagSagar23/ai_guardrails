import 'package:flutter/material.dart';
import 'package:ai_guardrails/ai_guardrails.dart';

import '../providers/llm_provider.dart';
import '../providers/guard_config.dart';
import '../widgets/message_bubble.dart';
import '../widgets/guard_findings_card.dart';

class FlowScreen extends StatefulWidget {
  final LlmProvider? provider;
  final String locale;
  const FlowScreen({super.key, this.provider, this.locale = 'en'});

  @override
  State<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends State<FlowScreen> {
  final List<_FlowMessage> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  late final LlmProvider _llm;
  late FlowGuardSession _flowSession;

  @override
  void initState() {
    super.initState();
    _llm = widget.provider ?? MockFlowLlmProvider();
    _flowSession = GuardConfig.flowSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _flowSession.reset();
      _messages.clear();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || _flowSession.isTerminal) return;
    _controller.clear();

    final prevState = _flowSession.currentState;
    setState(() {
      _messages.add(_FlowMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final outcome = await _flowSession.run(
        input: text,
        llmCall: _llm.generate,
      );
      if (!mounted) return;

      final newState = _flowSession.currentState;
      final transitioned = newState != prevState;

      setState(() {
        if (outcome.blocked) {
          _messages.add(_FlowMessage(
            text: outcome.blockReason ?? 'Blocked by flow guardrails.',
            isUser: false,
            outcome: outcome,
          ));
        } else {
          _messages[_messages.length - 1] = _FlowMessage(
            text: text,
            isUser: true,
            outcome: outcome,
          );
          _messages.add(_FlowMessage(
            text: outcome.output ?? outcome.rawOutput ?? '',
            isUser: false,
            outcome: outcome,
            stateTransition: transitioned ? '$prevState → $newState' : null,
          ));
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_FlowMessage(text: 'Error: $e', isUser: false));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  List<ScanResult> _outputFindings(GuardOutcome? outcome) {
    if (outcome == null) return [];
    return outcome.outputResults.where((r) => r.hasFindings).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final flow = _flowSession.flow;
    final current = _flowSession.currentState;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: cs.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_tree, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Flow: ${flow.name}', style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in flow.states.keys)
                    ChoiceChip(
                      label: Text(name),
                      selected: name == current,
                      selectedColor: flow.states[name]!.terminal
                          ? cs.errorContainer
                          : cs.primaryContainer,
                      onSelected: null,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (_flowSession.stateHistory.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _flowSession.stateHistory.join(' → '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Try: "Hello!", then "I need help with billing"\n'
                      'Try off-topic in billing: "what\'s the weather?"\n'
                      'End with: "thanks, bye"',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      );
                    }

                    final msg = _messages[index];
                    final isBlocked =
                        !msg.isUser && msg.outcome?.blocked == true;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: msg.isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (msg.stateTransition != null)
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Chip(
                                  avatar: Icon(Icons.arrow_forward,
                                      size: 16, color: cs.primary),
                                  label: Text(msg.stateTransition!),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          if (msg.isUser &&
                              msg.outcome != null &&
                              msg.outcome!.piiMap.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Chip(
                                avatar: Icon(Icons.shield_outlined,
                                    size: 16, color: cs.primary),
                                label: const Text('PII redacted'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          if (isBlocked)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.block,
                                      color: cs.onErrorContainer, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      msg.text,
                                      style:
                                          TextStyle(color: cs.onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            MessageBubble(
                              text: msg.text,
                              isUser: msg.isUser,
                              outcome: msg.outcome,
                            ),
                          if (!msg.isUser &&
                              !isBlocked &&
                              _outputFindings(msg.outcome).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GuardFindingsCard(
                                results: _outputFindings(msg.outcome),
                                locale: widget.locale,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _reset,
                  tooltip: 'Reset flow',
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_flowSession.isTerminal,
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: _flowSession.isTerminal
                          ? 'Conversation ended — tap reset'
                          : 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed:
                      _isLoading || _flowSession.isTerminal ? null : _send,
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowMessage {
  final String text;
  final bool isUser;
  final GuardOutcome? outcome;
  final String? stateTransition;

  const _FlowMessage({
    required this.text,
    required this.isUser,
    this.outcome,
    this.stateTransition,
  });
}
