import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ai_guardrails/ai_guardrails.dart';
import '../providers/llm_provider.dart';
import '../providers/guard_config.dart';
import '../widgets/guard_findings_card.dart';

class RagScreen extends StatefulWidget {
  final List<String>? initialCorpus;
  final String locale;
  const RagScreen({super.key, this.initialCorpus, this.locale = 'en'});

  @override
  State<RagScreen> createState() => _RagScreenState();
}

class _RagScreenState extends State<RagScreen> {
  List<String> _corpus = [];
  List<ChunkResult> _retrievalResults = [];
  String? _answer;
  GuardOutcome? _answerOutcome;
  bool _isLoading = false;
  bool _corpusLoaded = false;
  final _questionController = TextEditingController();

  static const _assetFiles = [
    'assets/knowledge_base/product_faq.txt',
    'assets/knowledge_base/company_policies.txt',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCorpus != null) {
      _corpus = widget.initialCorpus!;
      _corpusLoaded = true;
    } else {
      _loadCorpus();
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadCorpus() async {
    final chunks = <String>[];
    for (final path in _assetFiles) {
      try {
        final text = await rootBundle.loadString(path);
        chunks.addAll(
          text
              .split(RegExp(r'\n\n+'))
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty),
        );
      } catch (_) {
        // Asset missing — skip silently in demo.
      }
    }
    if (!mounted) return;
    setState(() {
      _corpus = chunks;
      _corpusLoaded = true;
    });
  }

  Future<void> _ask() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _corpus.isEmpty) return;

    setState(() {
      _isLoading = true;
      _answer = null;
      _answerOutcome = null;
      _retrievalResults = [];
    });

    // 1. Retrieval guard — scan chunks before feeding to LLM.
    final retrievalGuard = GuardConfig.retrievalGuard();
    final retrievalResult = await retrievalGuard.runRetrievalStage(_corpus);

    final accepted = retrievalResult.accepted;
    final context = accepted.join('\n\n');

    // 2. RAG guard — scan input+output around the LLM call.
    // Swap MockRagLlmProvider for CliLlmProvider to use real AI:
    //   CliLlmProvider('claude', ['-p'])
    final ragGuard = GuardConfig.ragGuard(context: context);
    final LlmProvider ragProvider = MockRagLlmProvider(context: context);
    final outcome = await ragGuard.run(
      input: '$question\n\nContext:\n$context',
      llmCall: ragProvider.generate,
    );

    if (!mounted) return;
    setState(() {
      _retrievalResults = retrievalResult.chunks;
      _answer = outcome.blocked ? null : outcome.output;
      _answerOutcome = outcome;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Knowledge Base section ──
          Text('Knowledge Base',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!_corpusLoaded)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  avatar: Icon(Icons.check_circle, color: cs.primary, size: 18),
                  label: Text('${_corpus.length} chunks loaded'),
                ),
                for (final name in _assetFiles)
                  Chip(
                    label: Text(name.split('/').last),
                  ),
              ],
            ),
          const SizedBox(height: 24),

          // ── Ask a Question section ──
          Text(
            'Ask a Question',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  decoration: const InputDecoration(
                    hintText: 'Type your question...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _ask(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isLoading || !_corpusLoaded || _corpus.isEmpty
                    ? null
                    : _ask,
                icon: _isLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Ask'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Retrieved Chunks section ──
          if (_retrievalResults.isNotEmpty) ...[
            Text(
              'Retrieved Chunks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...List.generate(_retrievalResults.length, (i) {
              final chunk = _retrievalResults[i];
              final preview = chunk.originalChunk.length > 120
                  ? '${chunk.originalChunk.substring(0, 120)}...'
                  : chunk.originalChunk;
              return ListTile(
                leading: Icon(
                  chunk.passed ? Icons.check_circle : Icons.cancel,
                  color: chunk.passed ? Colors.green : cs.error,
                ),
                title: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: chunk.passed
                    ? null
                    : Text(
                        chunk.dropReason ?? 'Blocked',
                        style: TextStyle(color: cs.error),
                      ),
              );
            }),
            const SizedBox(height: 24),
          ],

          // ── Answer section ──
          if (_answerOutcome != null) ...[
            Text('Answer', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_answerOutcome!.blocked)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.block, color: cs.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _answerOutcome!.blockReason ?? 'Blocked',
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_answer ?? ''),
                ),
              ),
            const SizedBox(height: 12),
            GuardFindingsCard(
              results: _answerOutcome!.outputResults,
              locale: widget.locale,
            ),
          ],
        ],
      ),
    );
  }
}
