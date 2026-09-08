import 'ai_guard.dart';
import 'scanner.dart';
import 'scanner_registry.dart';

/// Pre-built scanner + threshold bundles for common industry verticals.
///
/// Each profile is an overridable starting point — pick one, then customize.
///
/// ```dart
/// final guard = PolicyProfile.healthcare.toGuard();
/// ```
class PolicyProfile {
  /// Strict PII redaction, HIPAA-aligned defaults.
  static const healthcare = PolicyProfile._(
    'healthcare',
    config: {
      'inputScanners': [
        {
          'type': 'pii',
          'action': 'redact',
          'locales': ['us']
        },
        {'type': 'secret'},
        {'type': 'prompt_injection', 'threshold': 0.4},
        {'type': 'invisible_text'},
      ],
      'outputScanners': [
        {
          'type': 'pii',
          'action': 'redact',
          'locales': ['us']
        },
        {'type': 'repetition', 'threshold': 0.3},
      ],
      'rules': [
        {
          'when': {'any': 'pii.*'},
          'then': 'block'
        },
        {
          'when': {'any': 'secret.*'},
          'then': 'block'
        },
      ],
      'failClosed': true,
    },
  );

  /// PCI patterns, credit-card enforcement, financial data protection.
  static const finance = PolicyProfile._(
    'finance',
    config: {
      'inputScanners': [
        {
          'type': 'pii',
          'action': 'redact',
          'locales': ['us']
        },
        {'type': 'secret'},
        {'type': 'prompt_injection'},
        {'type': 'invisible_text'},
      ],
      'outputScanners': [
        {
          'type': 'pii',
          'action': 'redact',
          'locales': ['us']
        },
        {'type': 'repetition', 'threshold': 0.3},
        {'type': 'code_exec'},
      ],
      'rules': [
        {
          'when': {'any': 'pii.credit_card'},
          'then': 'block'
        },
        {
          'when': {'any': 'secret.*'},
          'then': 'block'
        },
        {
          'when': {'count': 'pii.*', 'gt': 3},
          'then': 'block'
        },
      ],
      'failClosed': true,
    },
  );

  /// Age-appropriate content, URL filtering, code-execution prevention.
  static const education = PolicyProfile._(
    'education',
    config: {
      'inputScanners': [
        {'type': 'prompt_injection'},
        {'type': 'invisible_text'},
        {'type': 'url'},
      ],
      'outputScanners': [
        {'type': 'repetition', 'threshold': 0.3},
        {'type': 'code_exec'},
        {'type': 'url'},
      ],
      'rules': [
        {
          'when': {'any': 'url.*'},
          'then': 'block'
        },
        {
          'when': {'any': 'code_exec.*'},
          'then': 'block'
        },
      ],
      'failClosed': true,
    },
  );

  /// Data loss prevention defaults — broad PII coverage, secret detection.
  static const enterprise = PolicyProfile._(
    'enterprise',
    config: {
      'inputScanners': [
        {'type': 'pii', 'action': 'redact'},
        {'type': 'secret'},
        {'type': 'prompt_injection', 'threshold': 0.4},
        {'type': 'invisible_text'},
        {'type': 'token_limit', 'maxTokens': 8192},
      ],
      'outputScanners': [
        {'type': 'pii', 'action': 'redact'},
        {'type': 'secret'},
        {'type': 'repetition', 'threshold': 0.3},
        {'type': 'code_exec'},
      ],
      'rules': [
        {
          'when': {'count': 'pii.*', 'gt': 5},
          'then': 'block'
        },
        {
          'when': {'any': 'secret.*'},
          'then': 'block'
        },
      ],
      'failClosed': true,
    },
  );

  static const values = [healthcare, finance, education, enterprise];

  final String name;

  /// The raw JSON config — merge/override before building.
  final Map<String, dynamic> config;

  const PolicyProfile._(this.name, {required this.config});

  /// Build an [AiGuard] from this profile.
  AiGuard toGuard({
    ScannerRegistry? registry,
    LlmCallback? llmCallback,
    void Function(dynamic)? onScan,
    void Function(dynamic)? onMetrics,
  }) =>
      AiGuard.fromConfig(config, registry: registry, llmCallback: llmCallback);

  /// Build an [AiGuard] from this profile with config overrides applied.
  ///
  /// [overrides] are merged on top of the profile defaults. Keys in
  /// [overrides] replace same-named keys in the profile config.
  AiGuard toGuardWith(
    Map<String, dynamic> overrides, {
    ScannerRegistry? registry,
    LlmCallback? llmCallback,
  }) {
    final merged = {...config, ...overrides};
    return AiGuard.fromConfig(merged,
        registry: registry, llmCallback: llmCallback);
  }

  /// Look up a profile by name.
  static PolicyProfile? byName(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }

  @override
  String toString() => 'PolicyProfile($name)';
}
