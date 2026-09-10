import 'package:flutter/material.dart';
import 'package:ai_guardrails/ai_guardrails.dart';

import '../providers/llm_provider.dart';
import '../providers/guard_config.dart';
import '../widgets/message_bubble.dart';
import '../widgets/guard_findings_card.dart';

class EscalationScreen extends StatefulWidget {
  final LlmProvider? provider;
  final String locale;
  const EscalationScreen({super.key, this.provider, this.locale = 'en'});

  @override
  State<EscalationScreen> createState() => _EscalationScreenState();
}

class _EscalationScreenState extends State<EscalationScreen> {
  final List<_EscMessage> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  late final LlmProvider _llm;
  late GuardSession _session;

  @override
  void initState() {
    super.initState();
    _llm = widget.provider ?? MockLlmProvider();
    _session = GuardConfig.escalationSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _session.reset();
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
    if (text.isEmpty || _isLoading) return;
    _controller.clear();

    setState(() {
      _messages.add(_EscMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final outcome = await _session.run(
        input: text,
        llmCall: _llm.generate,
      );
      if (!mounted) return;

      setState(() {
        _messages[_messages.length - 1] = _EscMessage(
          text: text,
          isUser: true,
          outcome: outcome,
        );
        if (outcome.blocked) {
          _messages.add(_EscMessage(
            text: outcome.blockReason ?? 'Blocked',
            isUser: false,
            outcome: outcome,
          ));
        } else {
          _messages.add(_EscMessage(
            text: outcome.output ?? outcome.rawOutput ?? '',
            isUser: false,
            outcome: outcome,
          ));
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_EscMessage(text: 'Error: $e', isUser: false));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  int get _totalFindings =>
      _session.turnHistory.fold<int>(0, (sum, o) => sum + o.allFindings.length);

  Color _levelColor(EscalationLevel level) => switch (level) {
        EscalationLevel.warn => Colors.green,
        EscalationLevel.block => Colors.orange,
        EscalationLevel.terminate => Colors.red,
      };

  IconData _levelIcon(EscalationLevel level) => switch (level) {
        EscalationLevel.warn => Icons.info_outline,
        EscalationLevel.block => Icons.warning_amber,
        EscalationLevel.terminate => Icons.block,
      };

  List<ScanResult> _allFindings(GuardOutcome outcome) => [
        ...outcome.inputResults.where((r) => r.hasFindings),
        ...outcome.outputResults.where((r) => r.hasFindings),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final level = _session.escalationLevel;
    final color = _levelColor(level);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: color.withValues(alpha: 0.15),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_levelIcon(level), color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Level: ${level.name.toUpperCase()}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Turn ${_session.turnCount} · '
                    '$_totalFindings findings',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_totalFindings / 5).clamp(0.0, 1.0),
                  backgroundColor: cs.surfaceContainerHighest,
                  color: color,
                  minHeight: 6,
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
                      'Send PII to trigger escalation:\n\n'
                      '"my email is test@example.com"\n'
                      '"contact me at demo@test.com"\n'
                      '"reach me at user@mail.com"\n\n'
                      '3 findings → BLOCK · 5 findings → TERMINATE',
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
                              msg.outcome != null &&
                              _allFindings(msg.outcome!).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GuardFindingsCard(
                                results: _allFindings(msg.outcome!),
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
                  tooltip: 'Reset session',
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: level == EscalationLevel.terminate
                          ? 'Session terminated — tap reset'
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
                  onPressed: _isLoading ? null : _send,
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

class _EscMessage {
  final String text;
  final bool isUser;
  final GuardOutcome? outcome;

  const _EscMessage({
    required this.text,
    required this.isUser,
    this.outcome,
  });
}
