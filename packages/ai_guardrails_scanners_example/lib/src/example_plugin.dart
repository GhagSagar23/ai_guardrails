import 'package:ai_guardrails/ai_guardrails.dart';

import 'profanity_scanner.dart';
import 'word_count_scanner.dart';

/// Example scanner plugin demonstrating the `ScannerPlugin` convention.
///
/// Install via [ScannerHub]:
/// ```dart
/// final hub = ScannerHub();
/// hub.install(ExamplePlugin());
/// ```
///
/// Or use the top-level const:
/// ```dart
/// hub.install(examplePlugin);
/// ```
class ExamplePlugin extends ScannerPlugin {
  /// Creates an [ExamplePlugin].
  ExamplePlugin();

  @override
  String get name => 'example';

  @override
  String get version => '0.1.0';

  @override
  String get description =>
      'Example scanners (profanity, word count) for plugin authors.';

  @override
  List<String> get scannerNames => const ['profanity', 'word_count'];

  @override
  void register(ScannerRegistry registry) {
    registry.register('profanity', (cfg) {
      final words = (cfg['words'] as List?)?.cast<String>().toSet();
      return ProfanityScanner(
        words: words,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );
    });
    registry.register('word_count', (cfg) {
      return WordCountScanner(
        maxWords: cfg['maxWords'] as int? ?? 500,
        action: parseGuardAction(cfg['action'] as String?) ?? GuardAction.block,
      );
    });
  }
}

/// Convenient instance for installation.
final examplePlugin = ExamplePlugin();
