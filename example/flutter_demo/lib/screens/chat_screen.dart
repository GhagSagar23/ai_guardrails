import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:ai_guardrails/ai_guardrails.dart';

import '../providers/llm_provider.dart';
import '../providers/guard_config.dart';
import '../widgets/message_bubble.dart';
import '../widgets/guard_findings_card.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final GuardOutcome? outcome;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.outcome,
    required this.timestamp,
  });
}

class ChatScreen extends StatefulWidget {
  final LlmProvider? provider;
  final String locale;
  const ChatScreen({super.key, this.provider, this.locale = 'en'});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  static bool get _canUseCli =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  late final LlmProvider _llmProvider;
  late final AiGuard _guard;
  late final GuardedLlmCall _guardedCall;

  @override
  void initState() {
    super.initState();
    _llmProvider = widget.provider ??
        (_canUseCli ? CliLlmProvider('claude', ['-p']) : MockLlmProvider());
    _guard = GuardConfig.chatGuard();
    _guardedCall = GuardedLlmCall(guard: _guard, maxReasks: 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final outcome = await _guardedCall.call(
        input: text,
        llmCall: (sanitised) => _llmProvider.generate(sanitised),
      );

      if (!mounted) return;
      setState(() {
        if (outcome.blocked) {
          // Update user message with outcome so badge can show PII info
          _messages[_messages.length - 1] = ChatMessage(
            text: text,
            isUser: true,
            outcome: outcome,
            timestamp: _messages.last.timestamp,
          );
          _messages.add(ChatMessage(
            text:
                'Blocked: ${outcome.blockReason ?? 'Request was blocked by guardrails.'}',
            isUser: false,
            outcome: outcome,
            timestamp: DateTime.now(),
          ));
        } else {
          // Update user message with outcome for PII badge
          _messages[_messages.length - 1] = ChatMessage(
            text: text,
            isUser: true,
            outcome: outcome,
            timestamp: _messages.last.timestamp,
          );
          _messages.add(ChatMessage(
            text: outcome.output ?? outcome.rawOutput ?? '',
            isUser: false,
            outcome: outcome,
            timestamp: DateTime.now(),
          ));
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: $e',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  bool _hasPiiRedacted(GuardOutcome? outcome) {
    if (outcome == null) return false;
    return outcome.piiMap.isNotEmpty;
  }

  List<ScanResult> _outputFindings(GuardOutcome? outcome) {
    if (outcome == null) return [];
    return outcome.outputResults.where((r) => r.findings.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'Send a message to start chatting',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
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
                      // Loading indicator
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _TypingIndicator(),
                        ),
                      );
                    }

                    final message = _messages[index];
                    final isBlocked = !message.isUser &&
                        message.outcome != null &&
                        message.outcome!.blocked;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: message.isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // PII redacted badge on user messages
                          if (message.isUser &&
                              _hasPiiRedacted(message.outcome))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Chip(
                                avatar: Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                                label: const Text('PII redacted'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),

                          // Blocked system message
                          if (isBlocked)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.block,
                                    color: colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      message.text,
                                      style: TextStyle(
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            MessageBubble(
                              text: message.text,
                              isUser: message.isUser,
                              outcome: message.outcome,
                            ),

                          // Output findings card for assistant messages
                          if (!message.isUser &&
                              !isBlocked &&
                              _outputFindings(message.outcome).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GuardFindingsCard(
                                results: _outputFindings(message.outcome),
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
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _sendMessage(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
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
                  onPressed: _isLoading ? null : _sendMessage,
                  tooltip: 'Send message',
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i * 0.2;
              final t = (_controller.value - delay).clamp(0.0, 1.0);
              final y = -4 * (1 - (2 * t - 1) * (2 * t - 1));
              return Transform.translate(
                offset: Offset(0, y),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
