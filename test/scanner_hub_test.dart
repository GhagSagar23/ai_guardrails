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

class _FakePlugin implements ScannerPlugin {
  @override
  final String name;
  final List<String> scannerNames;
  _FakePlugin(this.name, this.scannerNames);

  @override
  void register(ScannerRegistry registry) {
    for (final n in scannerNames) {
      registry.registerInstance(n, _TestScanner(n));
    }
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
}
