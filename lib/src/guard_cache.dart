import 'fnv.dart';
import 'scanner.dart';

/// Pluggable cache backend. Implement for Redis, Hive, etc.
///
/// The default [InMemoryCache] is suitable for single-isolate use.
/// For cross-isolate or persistent caching, implement this interface
/// with your own storage layer.
abstract class CacheBackend {
  Future<Object?> get(String key);
  Future<void> set(String key, Object value, Duration ttl);
  Future<void> remove(String key);
  Future<void> clear();
}

class _Entry {
  final Object value;
  final DateTime expiresAt;
  _Entry(this.value, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory [CacheBackend] with LRU eviction and TTL expiry.
class InMemoryCache implements CacheBackend {
  final int maxEntries;
  final _store = <String, _Entry>{};

  InMemoryCache({this.maxEntries = 1000});

  @override
  Future<Object?> get(String key) async {
    final e = _store.remove(key);
    if (e == null) return null;
    if (e.isExpired) return null;
    _store[key] = e;
    return e.value;
  }

  @override
  Future<void> set(String key, Object value, Duration ttl) async {
    _store.remove(key);
    if (_store.length >= maxEntries) {
      _store.remove(_store.keys.first);
    }
    _store[key] = _Entry(value, DateTime.now().add(ttl));
  }

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();

  int get length => _store.length;
}

/// Caches [LlmCallback] and [EmbeddingCallback] results.
///
/// Content-hash keyed, TTL-based expiry. Wraps callbacks transparently
/// so repeated identical inputs return cached results.
///
/// ```dart
/// final cache = GuardCache();
/// final cachedLlm = cache.wrapLlm(myLlmCallback);
/// final guard = AiGuard(llmCallback: cachedLlm, ...);
/// print(cache.hitRate); // 0.0..1.0
/// ```
class GuardCache {
  final CacheBackend backend;
  final Duration defaultTtl;
  int _hits = 0;
  int _misses = 0;

  GuardCache({
    CacheBackend? backend,
    this.defaultTtl = const Duration(minutes: 5),
  }) : backend = backend ?? InMemoryCache();

  /// Wrap an [LlmCallback] with caching.
  LlmCallback wrapLlm(LlmCallback cb) => (prompt) async {
        final key = 'llm:${fnv1a(prompt)}:$prompt';
        final cached = await backend.get(key);
        if (cached != null) {
          _hits++;
          return cached as String;
        }
        _misses++;
        final result = await cb(prompt);
        await backend.set(key, result, defaultTtl);
        return result;
      };

  /// Wrap an [EmbeddingCallback] with caching.
  EmbeddingCallback wrapEmbedding(EmbeddingCallback cb) => (text) async {
        final key = 'emb:${fnv1a(text)}:$text';
        final cached = await backend.get(key);
        if (cached != null) {
          _hits++;
          return (cached as List).cast<double>();
        }
        _misses++;
        final result = await cb(text);
        await backend.set(key, result, defaultTtl);
        return result;
      };

  int get hits => _hits;
  int get misses => _misses;

  double get hitRate =>
      (_hits + _misses) == 0 ? 0.0 : _hits / (_hits + _misses);

  Future<void> clear() async {
    await backend.clear();
    _hits = 0;
    _misses = 0;
  }
}
