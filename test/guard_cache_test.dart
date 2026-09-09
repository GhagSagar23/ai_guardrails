import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryCache', () {
    test('stores and retrieves values', () async {
      final cache = InMemoryCache();
      await cache.set('k', 'v', const Duration(minutes: 1));
      expect(await cache.get('k'), 'v');
    });

    test('returns null for missing key', () async {
      final cache = InMemoryCache();
      expect(await cache.get('missing'), isNull);
    });

    test('expires entries after TTL', () async {
      final cache = InMemoryCache();
      await cache.set('k', 'v', Duration.zero);
      // Zero TTL = immediately expired
      await Future.delayed(const Duration(milliseconds: 10));
      expect(await cache.get('k'), isNull);
    });

    test('evicts oldest when full', () async {
      final cache = InMemoryCache(maxEntries: 2);
      await cache.set('a', 1, const Duration(minutes: 1));
      await cache.set('b', 2, const Duration(minutes: 1));
      await cache.set('c', 3, const Duration(minutes: 1));
      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), 2);
      expect(await cache.get('c'), 3);
    });

    test('LRU: get promotes to end', () async {
      final cache = InMemoryCache(maxEntries: 2);
      await cache.set('a', 1, const Duration(minutes: 1));
      await cache.set('b', 2, const Duration(minutes: 1));
      await cache.get('a'); // promote a
      await cache.set('c', 3, const Duration(minutes: 1)); // evicts b
      expect(await cache.get('a'), 1);
      expect(await cache.get('b'), isNull);
    });

    test('remove works', () async {
      final cache = InMemoryCache();
      await cache.set('k', 'v', const Duration(minutes: 1));
      await cache.remove('k');
      expect(await cache.get('k'), isNull);
    });

    test('clear empties store', () async {
      final cache = InMemoryCache();
      await cache.set('a', 1, const Duration(minutes: 1));
      await cache.set('b', 2, const Duration(minutes: 1));
      await cache.clear();
      expect(cache.length, 0);
    });
  });

  group('GuardCache', () {
    test('wrapLlm caches identical prompts', () async {
      var calls = 0;
      Future<String> llm(String prompt) async {
        calls++;
        return 'response to $prompt';
      }

      final cache = GuardCache();
      final cached = cache.wrapLlm(llm);

      final r1 = await cached('hello');
      final r2 = await cached('hello');
      expect(r1, r2);
      expect(calls, 1);
      expect(cache.hits, 1);
      expect(cache.misses, 1);
    });

    test('wrapLlm passes through different prompts', () async {
      var calls = 0;
      Future<String> llm(String prompt) async {
        calls++;
        return 'r$calls';
      }

      final cache = GuardCache();
      final cached = cache.wrapLlm(llm);

      final r1 = await cached('a');
      final r2 = await cached('b');
      expect(r1, isNot(r2));
      expect(calls, 2);
      expect(cache.misses, 2);
    });

    test('wrapEmbedding caches identical texts', () async {
      var calls = 0;
      Future<List<double>> embed(String text) async {
        calls++;
        return [1.0, 2.0];
      }

      final cache = GuardCache();
      final cached = cache.wrapEmbedding(embed);

      final r1 = await cached('hello');
      final r2 = await cached('hello');
      expect(r1, r2);
      expect(calls, 1);
    });

    test('hitRate starts at zero', () {
      final cache = GuardCache();
      expect(cache.hitRate, 0.0);
    });

    test('hitRate reflects usage', () async {
      final cache = GuardCache();
      final cached = cache.wrapLlm((p) async => 'r');

      await cached('a');
      await cached('a');
      await cached('b');
      // 1 hit (second 'a'), 2 misses (first 'a', first 'b')
      expect(cache.hits, 1);
      expect(cache.misses, 2);
      expect(cache.hitRate, closeTo(1 / 3, 0.01));
    });

    test('clear resets stats', () async {
      final cache = GuardCache();
      final cached = cache.wrapLlm((p) async => 'r');

      await cached('a');
      await cached('a');
      await cache.clear();
      expect(cache.hits, 0);
      expect(cache.misses, 0);
      expect(cache.hitRate, 0.0);
    });

    test('custom backend is used', () async {
      final backend = InMemoryCache(maxEntries: 1);
      final cache = GuardCache(backend: backend);
      final cached = cache.wrapLlm((p) async => 'r$p');

      await cached('a');
      await cached('b'); // evicts a
      await cached('a'); // miss
      expect(cache.misses, 3);
    });

    test('custom TTL controls expiry', () async {
      final cache = GuardCache(defaultTtl: Duration.zero);
      final cached = cache.wrapLlm((p) async => 'r');

      await cached('a');
      await Future.delayed(const Duration(milliseconds: 10));
      await cached('a'); // should be expired
      expect(cache.misses, 2);
    });
  });
}
