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
import 'scanners/padding_attack_scanner.dart';
import 'scanners/tool_output_scanner.dart';
import 'scanners/topic_safety_scanner.dart';
import 'scanners/url_scanner.dart';
import 'scanners/json_validator.dart';
import 'scanners/html_validator.dart';
import 'scanners/sql_validator.dart';
import 'scanners/url_format_validator.dart';
import 'scanners/range_validator.dart';
import 'scanners/choices_validator.dart';
import 'scanners/topic_allowlist_scanner.dart';
import 'scanners/competitor_mention_scanner.dart';
import 'scanners/bias_scanner.dart';
import 'scanners/politeness_scanner.dart';
import 'scanners/reading_level_scanner.dart';

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
    register('padding_attack', _buildPaddingAttack);
    register('tool_output', _buildToolOutput);
    register('hallucination', _buildHallucination);
    register('fact_check', _buildFactCheck);
    register('topic_safety', _buildTopicSafety);
    register('json_validator', _buildJsonValidator);
    register('html_validator', _buildHtmlValidator);
    register('sql_validator', _buildSqlValidator);
    register('url_format_validator', _buildUrlFormatValidator);
    register('range_validator', _buildRangeValidator);
    register('choices_validator', _buildChoicesValidator);
    register('topic_allowlist', _buildTopicAllowlist);
    register('competitor_mention', _buildCompetitorMention);
    register('bias', _buildBias);
    register('politeness', _buildPoliteness);
    register('reading_level', _buildReadingLevel);
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

  static ScannerBase _buildPaddingAttack(Map<String, dynamic> cfg) =>
      PaddingAttackScanner(
        entropyFloor: (cfg['entropyFloor'] as num?)?.toDouble() ?? 3.0,
        maxRunRatio: (cfg['maxRunRatio'] as num?)?.toDouble() ?? 0.1,
        minRunLength: cfg['minRunLength'] as int? ?? 5,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildToolOutput(Map<String, dynamic> cfg) {
    final cats = (cfg['categories'] as List?)?.map((c) {
      for (final cat in ToolOutputCategory.values) {
        if (cat.name == c) return cat;
      }
      throw ArgumentError('Unknown ToolOutputCategory: $c');
    }).toSet();
    return ToolOutputScanner(
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      categories: cats ?? ToolOutputCategory.values.toSet(),
    );
  }

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

  static ScannerBase _buildJsonValidator(Map<String, dynamic> cfg) =>
      JsonValidator(
        maxDepth: cfg['maxDepth'] as int? ?? 64,
        maxArrayLength: cfg['maxArrayLength'] as int? ?? 10000,
        maxKeyCount: cfg['maxKeyCount'] as int? ?? 1000,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildHtmlValidator(Map<String, dynamic> cfg) =>
      HtmlValidator(
        allowedTags: (cfg['allowedTags'] as List?)?.cast<String>().toSet(),
        allowedAttributes:
            (cfg['allowedAttributes'] as List?)?.cast<String>().toSet(),
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildSqlValidator(Map<String, dynamic> cfg) =>
      SqlValidator(
        allowedStatements:
            (cfg['allowedStatements'] as List?)?.cast<String>().toSet(),
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildUrlFormatValidator(Map<String, dynamic> cfg) =>
      UrlFormatValidator(
        allowedProtocols:
            (cfg['allowedProtocols'] as List?)?.cast<String>().toSet(),
        allowedDomains:
            (cfg['allowedDomains'] as List?)?.cast<String>().toSet(),
        blockCredentials: cfg['blockCredentials'] as bool? ?? true,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildRangeValidator(Map<String, dynamic> cfg) =>
      RangeValidator(
        min: (cfg['min'] as num?)?.toDouble(),
        max: (cfg['max'] as num?)?.toDouble(),
        minLength: cfg['minLength'] as int?,
        maxLength: cfg['maxLength'] as int?,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildChoicesValidator(Map<String, dynamic> cfg) =>
      ChoicesValidator(
        (cfg['choices'] as List).cast<String>(),
        caseSensitive: cfg['caseSensitive'] as bool? ?? false,
        trim: cfg['trim'] as bool? ?? true,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildTopicAllowlist(Map<String, dynamic> cfg) =>
      TopicAllowlistScanner(
        allowedTopics:
            (cfg['allowedTopics'] as List?)?.cast<String>() ?? const [],
        useLlm: cfg['useLlm'] as bool? ?? false,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildCompetitorMention(Map<String, dynamic> cfg) =>
      CompetitorMentionScanner(
        (cfg['competitors'] as List).cast<String>(),
        caseSensitive: cfg['caseSensitive'] as bool? ?? false,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );

  static ScannerBase _buildBias(Map<String, dynamic> cfg) => BiasScanner(
        useLlm: cfg['useLlm'] as bool? ?? false,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.warn,
      );

  static ScannerBase _buildPoliteness(Map<String, dynamic> cfg) {
    final target = cfg['targetRegister'] as String? ?? 'neutral';
    final register = ToneRegister.values.firstWhere(
      (r) => r.name == target,
      orElse: () => ToneRegister.neutral,
    );
    return PolitenessScanner(
      targetRegister: register,
      action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.warn,
    );
  }

  static ScannerBase _buildReadingLevel(Map<String, dynamic> cfg) =>
      ReadingLevelScanner(
        minGrade: (cfg['minGrade'] as num?)?.toDouble(),
        maxGrade: (cfg['maxGrade'] as num?)?.toDouble(),
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.warn,
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
    'transform' => GuardAction.transform,
    _ => throw ArgumentError('Unknown action: $s'),
  };
}
