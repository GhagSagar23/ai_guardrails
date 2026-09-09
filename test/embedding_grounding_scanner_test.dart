import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

Future<List<double>> _mockEmbed(String text) async {
  final words = text.toLowerCase().split(RegExp(r'\s+'));
  // Bag-of-words style: fixed 10-dim vector, each dim = hash of word mod 10
  final vec = List.filled(10, 0.0);
  for (final w in words) {
    final idx = w.codeUnits.fold(0, (s, c) => s + c) % 10;
    vec[idx] += 1.0;
  }
  // Normalize
  final norm =
      vec.fold(0.0, (s, v) => s + v * v);
  if (norm > 0) {
    final len = norm == 0 ? 1.0 : _sqrt(norm);
    for (var i = 0; i < vec.length; i++) {
      vec[i] /= len;
    }
  }
  return vec;
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 20; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

void main() {
  group('EmbeddingGroundingScanner', () {
    test('passes when output is similar to source', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['The cat sat on the mat'],
        threshold: 0.5,
      );
      scanner.embeddingCallback = _mockEmbed;

      final result =
          await scanner.scanAsync('The cat sat on the mat', stage: ScanStage.output);
      expect(result.passed, isTrue);
    });

    test('flags ungrounded output', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['Quantum computing uses qubits'],
        threshold: 0.99,
      );
      scanner.embeddingCallback = _mockEmbed;

      final result = await scanner.scanAsync(
          'Medieval castle architecture in Europe',
          stage: ScanStage.output);
      expect(result.findings, isNotEmpty);
      expect(result.findings.first.type, 'grounding.low_similarity');
    });

    test('empty text passes', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['some context'],
      );
      scanner.embeddingCallback = _mockEmbed;

      final result = await scanner.scanAsync('', stage: ScanStage.output);
      expect(result.passed, isTrue);
    });

    test('empty source chunks passes', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: [],
      );
      scanner.embeddingCallback = _mockEmbed;

      final result = await scanner.scanAsync('hello', stage: ScanStage.output);
      expect(result.passed, isTrue);
    });

    test('block action produces blocking result', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['Quantum computing'],
        threshold: 0.99,
        action: GuardAction.block,
      );
      scanner.embeddingCallback = _mockEmbed;

      final result = await scanner.scanAsync(
          'Completely unrelated text about giraffes',
          stage: ScanStage.output);
      expect(result.passed, isFalse);
    });

    test('NLI callback rescues failed embedding', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['The capital of France is Paris'],
        threshold: 0.99,
        nliCallback: (prompt) async => 'ENTAILED',
      );
      scanner.embeddingCallback = _mockEmbed;

      final result = await scanner.scanAsync(
          'Paris is the capital city of France',
          stage: ScanStage.output);
      expect(result.passed, isTrue);
    });

    test('NLI NOT_ENTAILED does not rescue', () async {
      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['The capital of France is Paris'],
        threshold: 0.99,
        nliCallback: (prompt) async => 'NOT_ENTAILED',
      );
      scanner.embeddingCallback = _mockEmbed;

      final result = await scanner.scanAsync(
          'Tokyo is the capital of Japan',
          stage: ScanStage.output);
      expect(result.findings, isNotEmpty);
    });

    test('caches source embeddings across calls', () async {
      var embedCalls = 0;
      Future<List<double>> countingEmbed(String text) async {
        embedCalls++;
        return _mockEmbed(text);
      }

      final scanner = EmbeddingGroundingScanner(
        sourceChunks: ['chunk one', 'chunk two'],
        threshold: 0.1,
      );
      scanner.embeddingCallback = countingEmbed;

      await scanner.scanAsync('test output one', stage: ScanStage.output);
      final callsAfterFirst = embedCalls;

      await scanner.scanAsync('test output two', stage: ScanStage.output);
      // Second call should only embed the new output, not re-embed sources
      expect(embedCalls, callsAfterFirst + 1);
    });

    test('output-stage only', () {
      final scanner = EmbeddingGroundingScanner(sourceChunks: []);
      expect(scanner.stages, equals({ScanStage.output}));
    });

    test('name is embedding_grounding', () {
      final scanner = EmbeddingGroundingScanner(sourceChunks: []);
      expect(scanner.name, 'embedding_grounding');
    });
  });

  group('cosineSimilarity', () {
    test('identical vectors return 1.0', () {
      final v = [1.0, 2.0, 3.0];
      expect(
          EmbeddingGroundingScanner.cosineSimilarity(v, v), closeTo(1.0, 0.001));
    });

    test('orthogonal vectors return 0.0', () {
      expect(
        EmbeddingGroundingScanner.cosineSimilarity([1, 0, 0], [0, 1, 0]),
        closeTo(0.0, 0.001),
      );
    });

    test('opposite vectors return -1.0', () {
      expect(
        EmbeddingGroundingScanner.cosineSimilarity([1, 0], [-1, 0]),
        closeTo(-1.0, 0.001),
      );
    });

    test('empty vectors return 0.0', () {
      expect(EmbeddingGroundingScanner.cosineSimilarity([], []), 0.0);
    });

    test('mismatched lengths return 0.0', () {
      expect(
          EmbeddingGroundingScanner.cosineSimilarity([1, 2], [1, 2, 3]), 0.0);
    });

    test('zero vector returns 0.0', () {
      expect(
        EmbeddingGroundingScanner.cosineSimilarity([0, 0, 0], [1, 2, 3]),
        0.0,
      );
    });
  });
}
