import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_perspective/ai_guardrails_perspective.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _MockClient extends http.BaseClient {
  final http.StreamedResponse Function(http.BaseRequest request) handler;
  int callCount = 0;
  bool closed = false;

  _MockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    return handler(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.StreamedResponse _jsonResponse(Object body, {int statusCode = 200}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
  );
}

void main() {
  group('PerspectiveScanner', () {
    test('clean text passes', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'TOXICITY': {
                'summaryScore': {'value': 0.1},
              },
            },
          }));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      final result = await scanner.scanAsync('hello there');

      expect(result.passed, isTrue);
      expect(result.findings, isEmpty);
    });

    test('toxic content blocks', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'TOXICITY': {
                'summaryScore': {'value': 0.9},
              },
            },
          }));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      final result = await scanner.scanAsync('you are terrible');

      expect(result.passed, isFalse);
      expect(result.findings, hasLength(1));
    });

    test('multiple attributes detected', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'TOXICITY': {
                'summaryScore': {'value': 0.9},
              },
              'INSULT': {
                'summaryScore': {'value': 0.8},
              },
            },
          }));
      final scanner = PerspectiveScanner(
        apiKey: 'k',
        client: client,
        attributes: {'TOXICITY', 'INSULT'},
      );

      final result = await scanner.scanAsync('some text');

      expect(result.findings, hasLength(2));
    });

    test('custom attribute set', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'THREAT': {
                'summaryScore': {'value': 0.9},
              },
            },
          }));
      final scanner = PerspectiveScanner(
        apiKey: 'k',
        client: client,
        attributes: {'THREAT'},
      );

      final result = await scanner.scanAsync('some text');

      expect(result.findings.single.type, 'perspective.threat');
    });

    test('custom threshold', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'TOXICITY': {
                'summaryScore': {'value': 0.6},
              },
            },
          }));
      final scanner =
          PerspectiveScanner(apiKey: 'k', client: client, threshold: 0.5);

      final result = await scanner.scanAsync('some text');

      expect(result.passed, isFalse);
    });

    test('warn action', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'TOXICITY': {
                'summaryScore': {'value': 0.9},
              },
            },
          }));
      final scanner = PerspectiveScanner(
        apiKey: 'k',
        client: client,
        action: GuardAction.warn,
      );

      final result = await scanner.scanAsync('some text');

      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('empty text passes without API call', () async {
      final client = _MockClient((_) => _jsonResponse({}));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      final result = await scanner.scanAsync('   ');

      expect(result.passed, isTrue);
      expect(client.callCount, 0);
    });

    test('finding types correctly formatted', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'SEVERE_TOXICITY': {
                'summaryScore': {'value': 0.9},
              },
            },
          }));
      final scanner = PerspectiveScanner(
        apiKey: 'k',
        client: client,
        attributes: {'SEVERE_TOXICITY'},
      );

      final result = await scanner.scanAsync('some text');

      expect(result.findings.single.type, 'perspective.severe_toxicity');
    });

    test('both stages supported', () async {
      final client = _MockClient((_) => _jsonResponse({'attributeScores': {}}));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      expect(scanner.stages, {ScanStage.input, ScanStage.output});
      final result =
          await scanner.scanAsync('some text', stage: ScanStage.output);
      expect(result.passed, isTrue);
    });

    test('score values preserved', () async {
      final client = _MockClient((_) => _jsonResponse({
            'attributeScores': {
              'TOXICITY': {
                'summaryScore': {'value': 0.873},
              },
            },
          }));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      final result = await scanner.scanAsync('some text');

      expect(result.findings.single.confidence, 0.873);
    });

    test('API error propagates', () async {
      final client =
          _MockClient((_) => _jsonResponse({'error': 'bad'}, statusCode: 500));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      expect(scanner.scanAsync('some text'), throwsA(isA<Exception>()));
    });

    test('close() works', () {
      final client = _MockClient((_) => _jsonResponse({}));
      final scanner = PerspectiveScanner(apiKey: 'k', client: client);

      scanner.close();

      expect(client.closed, isTrue);
    });
  });
}
