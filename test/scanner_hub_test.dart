import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

class _TestScanner extends Scanner {
  final String _name;
  _TestScanner(this._name);
  @override
  String get name => _name;
  @override
  Set<ScanStage> get stages => const {ScanStage.input};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.pass(name, text);
}

class _FakePlugin extends ScannerPlugin {
  @override
  final String name;
  @override
  final String version;
  @override
  final String description;
  @override
  final List<String> scannerNames;

  _FakePlugin(
    this.name,
    this.scannerNames, {
    this.version = '1.0.0',
    this.description = 'Test plugin.',
  });

  @override
  void register(ScannerRegistry registry) {
    for (final n in scannerNames) {
      registry.registerInstance(n, _TestScanner(n));
    }
  }
}

class _BadPlugin extends ScannerPlugin {
  @override
  final String name = 'bad';
  @override
  final String version = '1.0.0';
  @override
  final String description = 'Declares but does not register.';
  @override
  final List<String> scannerNames = const ['ghost'];

  @override
  void register(ScannerRegistry registry) {
    // Intentionally does not register 'ghost'.
  }
}

void main() {
  group('ScannerHub', () {
    late ScannerRegistry registry;
    late ScannerHub hub;

    setUp(() {
      registry = ScannerRegistry();
      hub = ScannerHub(registry: registry);
    });

    test('install registers scanners in registry', () {
      hub.install(_FakePlugin('brand', ['brand_voice']));
      expect(registry.has('brand_voice'), true);
    });

    test('plugins getter returns installed list', () {
      final plugin = _FakePlugin('brand', ['brand_voice']);
      hub.install(plugin);
      expect(hub.plugins, hasLength(1));
      expect(hub.plugins.first.name, 'brand');
    });

    test('installAll registers all plugins', () {
      hub.installAll([
        _FakePlugin('brand', ['brand_voice', 'brand_compliance']),
        _FakePlugin('medical', ['hipaa_check']),
      ]);
      expect(registry.has('brand_voice'), true);
      expect(registry.has('brand_compliance'), true);
      expect(registry.has('hipaa_check'), true);
      expect(hub.plugins, hasLength(2));
    });

    test('build registered scanner by name', () {
      hub.install(_FakePlugin('test', ['my_scanner']));
      final scanner = registry.build('my_scanner');
      expect(scanner.name, 'my_scanner');
    });

    test('empty hub has no plugins', () {
      expect(hub.plugins, isEmpty);
    });

    test('plugins list is unmodifiable', () {
      hub.install(_FakePlugin('test', ['a']));
      expect(() => (hub.plugins as List).add('x'), throwsA(anything));
    });

    test('multiple plugins can register different scanners', () {
      hub.install(_FakePlugin('p1', ['scanner_a']));
      hub.install(_FakePlugin('p2', ['scanner_b']));
      expect(registry.has('scanner_a'), true);
      expect(registry.has('scanner_b'), true);
    });

    test('default registry is singleton', () {
      final defaultHub = ScannerHub();
      expect(defaultHub.registry, same(ScannerRegistry.instance));
    });

    test('unregister does not affect other plugins', () {
      hub.install(_FakePlugin('p1', ['a']));
      hub.install(_FakePlugin('p2', ['b']));
      registry.unregister('a');
      expect(registry.has('a'), false);
      expect(registry.has('b'), true);
    });
  });

  group('ScannerHub conflict detection', () {
    late ScannerRegistry registry;
    late ScannerHub hub;

    setUp(() {
      registry = ScannerRegistry();
      hub = ScannerHub(registry: registry);
    });

    test('throws on duplicate scanner name', () {
      hub.install(_FakePlugin('p1', ['shared_name']));
      expect(
        () => hub.install(_FakePlugin('p2', ['shared_name'])),
        throwsA(isA<ScannerConflictException>()),
      );
    });

    test('conflict exception reports plugin names', () {
      hub.install(_FakePlugin('alpha', ['scanner_x']));
      try {
        hub.install(_FakePlugin('beta', ['scanner_x']));
        fail('should throw');
      } on ScannerConflictException catch (e) {
        expect(e.scannerName, 'scanner_x');
        expect(e.pluginName, 'beta');
        expect(e.existingOwner, 'alpha');
        expect(e.toString(), contains('beta'));
        expect(e.toString(), contains('alpha'));
      }
    });

    test('force overwrites existing registration', () {
      hub.install(_FakePlugin('p1', ['overwrite_me']));
      hub.install(_FakePlugin('p2', ['overwrite_me']), force: true);
      expect(hub.ownerOf('overwrite_me'), 'p2');
      expect(registry.has('overwrite_me'), true);
    });

    test('conflict against built-in scanner', () {
      registry.registerInstance('pii', _TestScanner('pii'));
      expect(
        () => hub.install(_FakePlugin('custom', ['pii'])),
        throwsA(isA<ScannerConflictException>()),
      );
    });

    test('force against built-in scanner succeeds', () {
      registry.registerInstance('pii', _TestScanner('pii'));
      hub.install(_FakePlugin('custom', ['pii']), force: true);
      expect(hub.ownerOf('pii'), 'custom');
    });
  });

  group('ScannerHub metadata', () {
    late ScannerRegistry registry;
    late ScannerHub hub;

    setUp(() {
      registry = ScannerRegistry();
      hub = ScannerHub(registry: registry);
    });

    test('describe returns plugin info', () {
      hub.install(_FakePlugin(
        'brand',
        ['brand_voice', 'brand_compliance'],
        version: '2.1.0',
        description: 'Brand safety scanners.',
      ));
      final info = hub.describe();
      expect(info, hasLength(1));
      expect(info.first.name, 'brand');
      expect(info.first.version, '2.1.0');
      expect(info.first.description, 'Brand safety scanners.');
      expect(info.first.scannerNames, ['brand_voice', 'brand_compliance']);
    });

    test('describe with multiple plugins', () {
      hub.installAll([
        _FakePlugin('a', ['s1']),
        _FakePlugin('b', ['s2', 's3']),
      ]);
      final info = hub.describe();
      expect(info, hasLength(2));
      expect(info.map((i) => i.name), containsAll(['a', 'b']));
    });

    test('ownerOf returns plugin name', () {
      hub.install(_FakePlugin('medical', ['hipaa']));
      expect(hub.ownerOf('hipaa'), 'medical');
    });

    test('ownerOf returns null for unknown', () {
      expect(hub.ownerOf('nonexistent'), isNull);
    });

    test('has checks installed plugins', () {
      hub.install(_FakePlugin('test', ['s']));
      expect(hub.has('test'), true);
      expect(hub.has('missing'), false);
    });

    test('PluginInfo toString is readable', () {
      hub.install(_FakePlugin('x', ['a', 'b'], version: '1.0.0'));
      final info = hub.describe().first;
      expect(info.toString(), contains('x'));
      expect(info.toString(), contains('1.0.0'));
    });
  });

  group('ScannerHub uninstall', () {
    late ScannerRegistry registry;
    late ScannerHub hub;

    setUp(() {
      registry = ScannerRegistry();
      hub = ScannerHub(registry: registry);
    });

    test('uninstall removes plugin and its scanners', () {
      hub.install(_FakePlugin('brand', ['brand_voice', 'brand_tone']));
      expect(hub.has('brand'), true);
      expect(registry.has('brand_voice'), true);

      final removed = hub.uninstall('brand');
      expect(removed, true);
      expect(hub.has('brand'), false);
      expect(registry.has('brand_voice'), false);
      expect(registry.has('brand_tone'), false);
    });

    test('uninstall returns false for unknown plugin', () {
      expect(hub.uninstall('nonexistent'), false);
    });

    test('uninstall does not affect other plugins', () {
      hub.install(_FakePlugin('a', ['s1']));
      hub.install(_FakePlugin('b', ['s2']));
      hub.uninstall('a');
      expect(hub.has('b'), true);
      expect(registry.has('s2'), true);
    });

    test('uninstalled scanner name can be re-registered', () {
      hub.install(_FakePlugin('old', ['reusable']));
      hub.uninstall('old');
      hub.install(_FakePlugin('new', ['reusable']));
      expect(hub.ownerOf('reusable'), 'new');
    });
  });

  group('ScannerHub validation', () {
    late ScannerRegistry registry;
    late ScannerHub hub;

    setUp(() {
      registry = ScannerRegistry();
      hub = ScannerHub(registry: registry);
    });

    test('rejects plugin with empty name', () {
      expect(
        () => hub.install(_FakePlugin('', ['s'])),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects plugin with empty version', () {
      expect(
        () => hub.install(_FakePlugin('p', ['s'], version: '')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects plugin with no scanner names', () {
      expect(
        () => hub.install(_FakePlugin('p', [])),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects plugin that declares but does not register', () {
      expect(
        () => hub.install(_BadPlugin()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
