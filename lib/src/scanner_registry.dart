import 'scanner.dart';
import 'data/pii_patterns.dart';
import 'scanners/banned_pattern_scanner.dart';
import 'scanners/banned_topic_scanner.dart';
import 'scanners/code_execution_scanner.dart';
import 'scanners/fact_check_scanner.dart';
import 'scanners/grounding_scanner.dart';
import 'scanners/hallucination_scanner.dart';
import 'scanners/invisible_text_scanner.dart';
import 'scanners/language_scanner.dart';
import 'scanners/pii_scanner.dart';
import 'scanners/prompt_injection_scanner.dart';
import 'scanners/repetition_scanner.dart';
import 'scanners/schema_validator.dart';
import 'scanners/secret_scanner.dart';
import 'scanners/token_limit_scanner.dart';
import 'scanners/tool_call_scanner.dart';
import 'scanners/topic_safety_scanner.dart';
import 'scanners/url_scanner.dart';

/// Creates a [ScannerBase] from a JSON config map.
typedef ScannerFactory = ScannerBase Function(Map<String, dynamic> config);

/// Named scanner registration for dynamic lookup and config-driven loading.
///
/// Built-in scanners are auto-registered on the [instance] singleton.
/// Register custom scanners with [register] or [registerInstance].
///
/// ```dart
/// ScannerRegistry.instance.registerInstance('my_scanner', MyScanner());
/// final scanner = ScannerRegistry.instance.build('my_scanner');
/// ```
class ScannerRegistry {
  static final instance = ScannerRegistry._withBuiltins();

  final _factories = <String, ScannerFactory>{};

  ScannerRegistry();

  ScannerRegistry._withBuiltins() {
    registerBuiltins();
  }

  /// Register a factory that builds a scanner from config.
  void register(String name, ScannerFactory factory) {
    _factories[name] = factory;
  }

  /// Register a pre-built scanner instance (ignores config on build).
  void registerInstance(String name, ScannerBase scanner) {
    _factories[name] = (_) => scanner;
  }

  /// Remove a registered scanner.
  void unregister(String name) => _factories.remove(name);

  /// Whether a scanner with [name] is registered.
  bool has(String name) => _factories.containsKey(name);

  /// All registered scanner names.
  Iterable<String> get registered => _factories.keys;

  /// Build a scanner by name with optional config.
  ScannerBase build(String name, [Map<String, dynamic> config = const {}]) {
    final factory = _factories[name];
    if (factory == null) throw ArgumentError('Unknown scanner: $name');
    return factory(config);
  }

  /// Build a scanner by name, returning `null` if not registered.
  ScannerBase? tryBuild(String name, [Map<String, dynamic> config = const {}]) {
    final factory = _factories[name];
    return factory?.call(config);
  }

  /// Register all built-in scanners with their canonical names.
  void registerBuiltins() {
    register('pii', _buildPii);
    register('secret', _buildSecret);
    register('prompt_injection', _buildPromptInjection);
    register('invisible_text', _buildInvisibleText);
    register('banned_topic', _buildBannedTopic);
    register('banned_pattern', _buildBannedPattern);
    register('token_limit', _buildTokenLimit);
    register('repetition', _buildRepetition);
    register('url', _buildUrl);
    register('language', _buildLanguage);
    register('code_exec', _buildCodeExec);
    register('grounding', _buildGrounding);
    register('schema', _buildSchema);
    register('tool_call', _buildToolCall);
    register('hallucination', _buildHallucination);
    register('fact_check', _buildFactCheck);
    register('topic_safety', _buildTopicSafety);
  }

  // -- Built-in factories --

  static ScannerBase _buildPii(Map<String, dynamic> cfg) => PiiScanner(
        action:
            parseGuardAction(cfg['action'] as String?) ?? GuardAction.redact,
        locales: _parseLocales(cfg['locales']),
        types: (cfg['types'] as List?)?.cast<String>().toSet(),
      );

  static ScannerBase _buildSecret(Map<String, dynamic> cfg) => SecretScanner(
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block);

  static ScannerBase _buildPromptInjection(Map<String, dynamic> cfg) =>
      PromptInjectionScanner(
        threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.5,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildInvisibleText(Map<String, dynamic> cfg) =>
      InvisibleTextScanner(
          action:
              parseGuardAction(cfg['action'] as String?) ?? GuardAction.redact);

  static ScannerBase _buildBannedTopic(Map<String, dynamic> cfg) =>
      BannedTopicScanner(
        (cfg['topics'] as List).cast<String>(),
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
        caseSensitive: cfg['caseSensitive'] as bool? ?? false,
      );

  static ScannerBase _buildBannedPattern(Map<String, dynamic> cfg) {
    final patterns =
        (cfg['patterns'] as List).map((p) => RegExp(p as String)).toList();
    return BannedPatternScanner(
      patterns,
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      name: cfg['name'] as String? ?? 'banned_pattern',
    );
  }

  static ScannerBase _buildTokenLimit(Map<String, dynamic> cfg) =>
      TokenLimitScanner(
        maxTokens: cfg['maxTokens'] as int? ?? 4096,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildRepetition(Map<String, dynamic> cfg) =>
      RepetitionScanner(
        threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.3,
        ngramSize: cfg['ngramSize'] as int? ?? 3,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildUrl(Map<String, dynamic> cfg) => UrlScanner(
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block);

  static ScannerBase _buildLanguage(Map<String, dynamic> cfg) =>
      LanguageScanner(
        threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.7,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildCodeExec(Map<String, dynamic> cfg) =>
      CodeExecutionScanner(
          action:
              parseGuardAction(cfg['action'] as String?) ?? GuardAction.block);

  static ScannerBase _buildGrounding(Map<String, dynamic> cfg) =>
      GroundingScanner(
        context: cfg['context'] as String? ?? '',
        threshold: (cfg['threshold'] as num?)?.toDouble() ?? 0.5,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.warn,
      );

  static ScannerBase _buildSchema(Map<String, dynamic> cfg) => SchemaValidator(
        cfg['schema'] as Map<String, dynamic>,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildToolCall(Map<String, dynamic> cfg) =>
      ToolCallScanner(
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
        allowedTools: (cfg['allowedTools'] as List?)?.cast<String>().toSet(),
        deniedTools: (cfg['deniedTools'] as List?)?.cast<String>().toSet(),
        toolSchemas: (cfg['toolSchemas'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))),
        scanArguments: cfg['scanArguments'] as bool? ?? true,
        maxCallsPerTurn: cfg['maxCallsPerTurn'] as int? ?? 10,
        maxDepth: cfg['maxDepth'] as int? ?? 5,
      );

  static ScannerBase _buildHallucination(Map<String, dynamic> cfg) {
    final prompt = cfg['prompt'] as String?;
    if (prompt == null || prompt.isEmpty) {
      throw ArgumentError('hallucination scanner requires "prompt" in config');
    }
    return HallucinationScanner(
      prompt: prompt,
      sampleCount: cfg['sampleCount'] as int? ?? 3,
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.warn,
    );
  }

  static ScannerBase _buildFactCheck(Map<String, dynamic> cfg) {
    final context = cfg['context'] as String?;
    if (context == null || context.isEmpty) {
      throw ArgumentError('fact_check scanner requires "context" in config');
    }
    return FactCheckScanner(
      context: context,
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.warn,
    );
  }

  static ScannerBase _buildTopicSafety(Map<String, dynamic> cfg) =>
      TopicSafetyScanner(
        allowedTopics:
            (cfg['allowedTopics'] as List?)?.cast<String>() ?? const [],
        forbiddenTopics:
            (cfg['forbiddenTopics'] as List?)?.cast<String>() ?? const [],
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static Set<PiiLocale> _parseLocales(dynamic v) {
    if (v == null) return PiiLocale.values.toSet();
    return (v as List).map((s) {
      for (final locale in PiiLocale.values) {
        if (locale.name == s) return locale;
      }
      throw ArgumentError('Unknown locale: $s');
    }).toSet();
  }
}

/// Parse a [GuardAction] from its string name.
GuardAction? parseGuardAction(String? s) {
  if (s == null) return null;
  return switch (s) {
    'block' => GuardAction.block,
    'redact' => GuardAction.redact,
    'hash' => GuardAction.hash,
    'warn' => GuardAction.warn,
    _ => throw ArgumentError('Unknown action: $s'),
  };
}
