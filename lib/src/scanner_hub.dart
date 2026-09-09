import 'scanner_registry.dart';

/// Interface for scanner plugin packages.
///
/// Companion packages (e.g. `ai_guardrails_scanners_brand`) implement this
/// and export a const instance. Users install plugins via [ScannerHub].
///
/// ```dart
/// class BrandPlugin implements ScannerPlugin {
///   @override
///   String get name => 'brand';
///
///   @override
///   void register(ScannerRegistry registry) {
///     registry.register('brand_voice', (cfg) => BrandVoiceScanner());
///   }
/// }
/// ```
abstract class ScannerPlugin {
  /// Human-readable plugin name.
  String get name;

  /// Register all scanners from this plugin into [registry].
  void register(ScannerRegistry registry);
}

/// Central hub for installing scanner plugins.
///
/// ```dart
/// final hub = ScannerHub();
/// hub.installAll([BrandPlugin(), MedicalPlugin()]);
/// // Scanners now available via ScannerRegistry.instance
/// ```
class ScannerHub {
  final ScannerRegistry registry;
  final _plugins = <ScannerPlugin>[];

  ScannerHub({ScannerRegistry? registry})
      : registry = registry ?? ScannerRegistry.instance;

  /// Install a single plugin.
  void install(ScannerPlugin plugin) {
    plugin.register(registry);
    _plugins.add(plugin);
  }

  /// Install multiple plugins.
  void installAll(List<ScannerPlugin> plugins) {
    for (final p in plugins) {
      install(p);
    }
  }

  /// All installed plugins.
  List<ScannerPlugin> get plugins => List.unmodifiable(_plugins);
}
