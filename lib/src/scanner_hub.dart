import 'scanner.dart';
import 'scanner_registry.dart';

/// Interface for scanner plugin packages.
///
/// Companion packages (e.g. `ai_guardrails_scanners_brand`) implement this
/// and export a const instance. Users install plugins via [ScannerHub].
///
/// ```dart
/// class BrandPlugin extends ScannerPlugin {
///   const BrandPlugin();
///
///   @override
///   String get name => 'brand';
///
///   @override
///   String get version => '1.0.0';
///
///   @override
///   String get description => 'Brand voice and compliance scanners.';
///
///   @override
///   List<String> get scannerNames => ['brand_voice', 'brand_compliance'];
///
///   @override
///   void register(ScannerRegistry registry) {
///     registry.register('brand_voice', (cfg) => BrandVoiceScanner());
///     registry.register('brand_compliance', (cfg) => BrandComplianceScanner());
///   }
/// }
/// ```
abstract class ScannerPlugin {
  /// Human-readable plugin name (e.g. `'brand'`, `'medical'`).
  String get name;

  /// SemVer version string (e.g. `'1.0.0'`).
  String get version;

  /// One-line description of what this plugin provides.
  String get description;

  /// Names of all scanners this plugin will register.
  ///
  /// Must match exactly the names passed to [ScannerRegistry.register] inside
  /// [register]. Used by [ScannerHub] for conflict detection and reporting.
  List<String> get scannerNames;

  /// Register all scanners from this plugin into [registry].
  void register(ScannerRegistry registry);
}

/// Thrown when a plugin tries to register a scanner name that already exists.
class ScannerConflictException implements Exception {
  /// The conflicting scanner name.
  final String scannerName;

  /// The plugin that tried to register it.
  final String pluginName;

  /// The plugin that already owns the name, or `null` for built-in scanners.
  final String? existingOwner;

  /// Creates a [ScannerConflictException].
  const ScannerConflictException({
    required this.scannerName,
    required this.pluginName,
    this.existingOwner,
  });

  @override
  String toString() =>
      'ScannerConflictException: plugin "$pluginName" tried to register '
      '"$scannerName" but it is already registered'
      '${existingOwner != null ? ' by "$existingOwner"' : ''}.';
}

/// Installed plugin entry with ownership tracking.
class _InstalledPlugin {
  final ScannerPlugin plugin;
  final List<String> registeredNames;
  const _InstalledPlugin(this.plugin, this.registeredNames);
}

/// Summary of a single installed plugin, returned by [ScannerHub.describe].
class PluginInfo {
  /// Plugin name.
  final String name;

  /// Plugin version.
  final String version;

  /// Plugin description.
  final String description;

  /// Scanner names this plugin registered.
  final List<String> scannerNames;

  /// Creates a [PluginInfo].
  const PluginInfo({
    required this.name,
    required this.version,
    required this.description,
    required this.scannerNames,
  });

  @override
  String toString() => 'PluginInfo($name@$version: $scannerNames)';
}

/// Central hub for installing scanner plugins.
///
/// Tracks plugin ownership of scanner names, detects conflicts, and provides
/// a [describe] method for debugging.
///
/// ```dart
/// final hub = ScannerHub();
/// hub.install(BrandPlugin());
/// hub.install(MedicalPlugin());
/// // Scanners now available via ScannerRegistry.instance
/// print(hub.describe()); // list of installed plugins + scanners
/// ```
class ScannerHub {
  /// The scanner registry used to build scanners.
  final ScannerRegistry registry;
  final _installed = <_InstalledPlugin>[];
  final _ownership = <String, String>{}; // scanner name → plugin name

  /// Creates a [ScannerHub].
  ScannerHub({ScannerRegistry? registry})
      : registry = registry ?? ScannerRegistry.instance;

  /// Install a single plugin.
  ///
  /// Checks for name conflicts before registering. If [force] is `true`,
  /// existing registrations are overwritten instead of throwing.
  ///
  /// Throws [ScannerConflictException] when a scanner name is already
  /// registered and [force] is `false`.
  void install(ScannerPlugin plugin, {bool force = false}) {
    _validateManifest(plugin);
    _checkConflicts(plugin, force: force);
    plugin.register(registry);
    _verifyRegistered(plugin);
    final registered = <String>[];
    for (final name in plugin.scannerNames) {
      _ownership[name] = plugin.name;
      registered.add(name);
    }
    _installed.add(_InstalledPlugin(plugin, registered));
  }

  /// Install multiple plugins.
  void installAll(List<ScannerPlugin> plugins, {bool force = false}) {
    for (final p in plugins) {
      install(p, force: force);
    }
  }

  /// Uninstall a plugin by name, removing its scanners from the registry.
  ///
  /// Returns `true` if found and removed.
  bool uninstall(String pluginName) {
    final idx = _installed.indexWhere((e) => e.plugin.name == pluginName);
    if (idx < 0) return false;
    final entry = _installed.removeAt(idx);
    for (final name in entry.registeredNames) {
      registry.unregister(name);
      _ownership.remove(name);
    }
    return true;
  }

  /// All installed plugins.
  List<ScannerPlugin> get plugins =>
      List.unmodifiable(_installed.map((e) => e.plugin));

  /// Whether a plugin with [name] is installed.
  bool has(String name) => _installed.any((e) => e.plugin.name == name);

  /// Structured summary of all installed plugins and their scanners.
  List<PluginInfo> describe() => [
        for (final e in _installed)
          PluginInfo(
            name: e.plugin.name,
            version: e.plugin.version,
            description: e.plugin.description,
            scannerNames: List.unmodifiable(e.registeredNames),
          ),
      ];

  /// Which plugin owns a given scanner name, or `null` if built-in or unknown.
  String? ownerOf(String scannerName) => _ownership[scannerName];

  void _validateManifest(ScannerPlugin plugin) {
    if (plugin.name.isEmpty) {
      throw ArgumentError('Plugin name must not be empty.');
    }
    if (plugin.version.isEmpty) {
      throw ArgumentError('Plugin "${plugin.name}" version must not be empty.');
    }
    if (plugin.scannerNames.isEmpty) {
      throw ArgumentError(
          'Plugin "${plugin.name}" must declare at least one scanner name.');
    }
  }

  void _checkConflicts(ScannerPlugin plugin, {required bool force}) {
    for (final name in plugin.scannerNames) {
      if (registry.has(name)) {
        if (force) {
          registry.unregister(name);
          _ownership.remove(name);
        } else {
          throw ScannerConflictException(
            scannerName: name,
            pluginName: plugin.name,
            existingOwner: _ownership[name],
          );
        }
      }
    }
  }

  void _verifyRegistered(ScannerPlugin plugin) {
    for (final name in plugin.scannerNames) {
      if (!registry.has(name)) {
        throw StateError(
          'Plugin "${plugin.name}" declared scanner "$name" in scannerNames '
          'but did not register it. Check the register() implementation.',
        );
      }
      // ponytail: build with empty config to verify the factory doesn't throw.
      // Catches typos and missing defaults early, at install time.
      try {
        final scanner = registry.build(name);
        if (scanner is Scanner || scanner is AsyncScanner) {
          // valid
        }
      } catch (e) {
        registry.unregister(name);
        throw StateError(
          'Plugin "${plugin.name}" scanner "$name" failed build validation: $e',
        );
      }
    }
  }
}
