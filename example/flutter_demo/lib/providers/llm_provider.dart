import 'dart:convert';
import 'dart:io';

/// LLM providers for the ai_guardrails demo app.
///
/// [MockLlmProvider] returns canned responses that trigger various scanners.
/// [CliLlmProvider] shells out to a local CLI (claude, codex, agy, ollama).
abstract class LlmProvider {
  Future<String> generate(String prompt);
}

/// Calls a local CLI tool that accepts a prompt argument and returns text.
///
/// Works on Android, macOS, Linux, Windows — NOT web or iOS.
///
/// Usage:
/// ```dart
/// CliLlmProvider('claude', ['-p'])   // claude -p "prompt"
/// CliLlmProvider('codex', ['-q'])    // codex -q "prompt"
/// CliLlmProvider('agy', [])          // agy "prompt"
/// CliLlmProvider('ollama', ['run', 'llama3'])  // ollama run llama3 "prompt"
/// ```
class CliLlmProvider implements LlmProvider {
  final String command;
  final List<String> baseArgs;
  final String? systemPrompt;

  static const _defaultSystem =
      'You are a helpful customer support agent for Nimbus, a SaaS '
      'collaboration platform. Answer questions about Nimbus features, '
      'pricing, and policies. Be concise (2-4 sentences).';

  CliLlmProvider(this.command, [this.baseArgs = const [], this.systemPrompt]);

  @override
  Future<String> generate(String prompt) async {
    final result = await Process.run(
      command,
      [
        ...baseArgs,
        '--system-prompt',
        systemPrompt ?? _defaultSystem,
        prompt,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        command,
        baseArgs,
        'CLI failed (exit ${result.exitCode}): ${result.stderr}',
        result.exitCode,
      );
    }
    return (result.stdout as String).trim();
  }
}

class MockLlmProvider implements LlmProvider {
  @override
  Future<String> generate(String prompt) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final lower = prompt.toLowerCase();

    // Triggers PiiScanner (output stage) — contains email + phone.
    if (lower.contains('email') || lower.contains('contact')) {
      return 'You can reach our support team at john.smith@nimbus.io or '
          'call +1-555-867-5309. We typically respond within 24 hours.';
    }

    // Triggers CompetitorMentionScanner.
    if (lower.contains('competitor') ||
        lower.contains('alternative') ||
        lower.contains('compare')) {
      return 'Unlike Acme and Globex, our platform offers end-to-end '
          'encryption by default. We believe in privacy-first design.';
    }

    // Contains an email — triggers PiiScanner on output.
    if (lower.contains('price') ||
        lower.contains('cost') ||
        lower.contains('plan')) {
      return 'Our plans start at \$29/month for individuals. Team plans are '
          '\$99/month. Enterprise pricing is custom — contact '
          'sales@nimbus.io for a quote.';
    }

    // Triggers ReadingLevelScanner — deliberately too complex.
    if (lower.contains('technical') ||
        lower.contains('architecture') ||
        lower.contains('how does')) {
      return 'The system utilizes a microservices architecture with '
          'event-driven communication patterns. Furthermore, '
          'notwithstanding the aforementioned architectural considerations, '
          'the epistemological implications of our distributed consensus '
          'algorithm necessitate comprehensive evaluation of Byzantine '
          'fault tolerance paradigms.';
    }

    // Off-topic — benign response, no scanner triggers expected.
    if (lower.contains('weather') ||
        lower.contains('sports') ||
        lower.contains('politics')) {
      return 'That topic is outside my area of expertise. I can help with '
          'questions about our product, features, pricing, and technical '
          'details.';
    }

    return 'Thank you for your question. Based on our documentation, I can '
        'help you with that. Our platform provides comprehensive tools for '
        'team collaboration, project management, and secure file sharing. '
        'Would you like me to elaborate on any specific feature?';
  }
}

class MockRagLlmProvider implements LlmProvider {
  String _context;

  MockRagLlmProvider({String context = ''}) : _context = context;

  void setContext(String context) => _context = context;

  @override
  Future<String> generate(String prompt) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (_context.isEmpty) {
      return "I don't have enough context to answer that question. "
          'Please load a knowledge base first.';
    }

    final lower = prompt.toLowerCase();

    // Contains email — triggers PiiScanner on output.
    if (lower.contains('refund') || lower.contains('return')) {
      return 'According to our policy, refunds are available within 30 days '
          'of purchase. Contact support@nimbus.io to initiate a return.';
    }

    if (lower.contains('privacy') || lower.contains('data')) {
      return 'We take privacy seriously. All data is encrypted at rest using '
          'AES-256 and in transit using TLS 1.3. We never sell user data to '
          'third parties.';
    }

    if (lower.contains('feature') || lower.contains('what can')) {
      return 'Nimbus offers real-time collaboration, version control, '
          'automated backups, and enterprise SSO. Our unique feature is '
          'AI-powered search across all your documents.';
    }

    // Default: reference context to demonstrate grounding.
    final snippet =
        _context.length > 200 ? _context.substring(0, 200) : _context;
    return 'Based on the available documentation: $snippet... '
        'I hope this helps answer your question.';
  }
}
