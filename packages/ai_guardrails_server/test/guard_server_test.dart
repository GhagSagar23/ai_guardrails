import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_server/ai_guardrails_server.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _PassScanner extends Scanner {
  @override
  String get name => 'passer';
  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.pass(name, text);
}

class _BlockScanner extends Scanner {
  @override
  String get name => 'blocker';
  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.block(name, text,
          findings: [const Finding(type: 'blocker.test')],
          reason: 'test block');
}

class _MockBackend extends http.BaseClient {
  http.BaseRequest? lastRequest;

  static const _defaultResponse =
      '{"choices":[{"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode(_defaultResponse)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('GuardHandler', () {
    group('health', () {
      test('returns ok', () async {
        final handler = GuardHandler(guard: AiGuard());
        final response = await handler
            .call(Request('GET', Uri.parse('http://localhost/health')));
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['status'], 'ok');
      });
    });

    group('scan/input', () {
      test('clean text passes', () async {
        final handler =
            GuardHandler(guard: AiGuard(inputScanners: [_PassScanner()]));
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/scan/input'),
          body: jsonEncode({'text': 'hello'}),
          headers: {'content-type': 'application/json'},
        ));
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['passed'], true);
      });

      test('blocked text fails', () async {
        final handler =
            GuardHandler(guard: AiGuard(inputScanners: [_BlockScanner()]));
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/scan/input'),
          body: jsonEncode({'text': 'hello'}),
          headers: {'content-type': 'application/json'},
        ));
        final body = jsonDecode(await response.readAsString());
        expect(body['passed'], false);
        expect(body['results'], isNotEmpty);
      });

      test('returns processed text', () async {
        final handler =
            GuardHandler(guard: AiGuard(inputScanners: [_PassScanner()]));
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/scan/input'),
          body: jsonEncode({'text': 'hello'}),
          headers: {'content-type': 'application/json'},
        ));
        final body = jsonDecode(await response.readAsString());
        expect(body['processedText'], 'hello');
      });
    });

    group('scan/output', () {
      test('clean text passes', () async {
        final handler =
            GuardHandler(guard: AiGuard(outputScanners: [_PassScanner()]));
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/scan/output'),
          body: jsonEncode({'text': 'hello'}),
          headers: {'content-type': 'application/json'},
        ));
        final body = jsonDecode(await response.readAsString());
        expect(body['passed'], true);
      });
    });

    group('chat/completions', () {
      test('returns 502 when no backend configured', () async {
        final handler = GuardHandler(guard: AiGuard());
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/chat/completions'),
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ]
          }),
          headers: {'content-type': 'application/json'},
        ));
        expect(response.statusCode, 502);
      });

      test('proxies to backend and returns guarded response', () async {
        final backend = _MockBackend();
        final handler = GuardHandler(
          guard: AiGuard(
            inputScanners: [_PassScanner()],
            outputScanners: [_PassScanner()],
          ),
          backendUrl: 'http://llm-backend',
          client: backend,
        );
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/chat/completions'),
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ]
          }),
          headers: {'content-type': 'application/json'},
        ));
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['choices'][0]['message']['content'], 'Hello!');
        expect(response.headers['x-guard-blocked'], 'false');
      });

      test('blocks on input', () async {
        final backend = _MockBackend();
        final handler = GuardHandler(
          guard: AiGuard(inputScanners: [_BlockScanner()]),
          backendUrl: 'http://llm-backend',
          client: backend,
        );
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/chat/completions'),
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ]
          }),
          headers: {'content-type': 'application/json'},
        ));
        expect(response.statusCode, 400);
        expect(response.headers['x-guard-blocked'], 'true');
        expect(backend.lastRequest, isNull);
      });

      test('blocks on output', () async {
        final backend = _MockBackend();
        final handler = GuardHandler(
          guard: AiGuard(
            inputScanners: [_PassScanner()],
            outputScanners: [_BlockScanner()],
          ),
          backendUrl: 'http://llm-backend',
          client: backend,
        );
        final response = await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/chat/completions'),
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ]
          }),
          headers: {'content-type': 'application/json'},
        ));
        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], 'output_blocked');
      });

      test('passes authorization header to backend', () async {
        final backend = _MockBackend();
        final handler = GuardHandler(
          guard: AiGuard(),
          backendUrl: 'http://llm-backend',
          client: backend,
        );
        await handler.call(Request(
          'POST',
          Uri.parse('http://localhost/v1/chat/completions'),
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ]
          }),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer sk-test',
          },
        ));
        expect(backend.lastRequest?.headers['authorization'], 'Bearer sk-test');
      });
    });

    group('routing', () {
      test('unknown path returns 404', () async {
        final handler = GuardHandler(guard: AiGuard());
        final response = await handler
            .call(Request('GET', Uri.parse('http://localhost/unknown')));
        expect(response.statusCode, 404);
      });
    });
  });

  group('guardMiddleware', () {
    test('passes clean requests through', () async {
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        outputScanners: [_PassScanner()],
      );
      Future<Response> inner(Request r) async =>
          Response.ok('response', headers: {'content-type': 'text/plain'});
      final handler = const Pipeline()
          .addMiddleware(guardMiddleware(guard))
          .addHandler(inner);

      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: 'hello',
        headers: {'content-type': 'text/plain'},
      ));
      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'response');
    });

    test('blocks bad input', () async {
      final guard = AiGuard(inputScanners: [_BlockScanner()]);
      Future<Response> inner(Request r) async => Response.ok('response');
      final handler = const Pipeline()
          .addMiddleware(guardMiddleware(guard))
          .addHandler(inner);

      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: 'bad input',
        headers: {'content-type': 'text/plain'},
      ));
      expect(response.statusCode, 400);
      expect(response.headers['x-guard-blocked'], 'true');
    });

    test('blocks bad output', () async {
      final guard = AiGuard(outputScanners: [_BlockScanner()]);
      Future<Response> inner(Request r) async =>
          Response.ok('bad output', headers: {'content-type': 'text/plain'});
      final handler = const Pipeline()
          .addMiddleware(guardMiddleware(guard))
          .addHandler(inner);

      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: 'hello',
        headers: {'content-type': 'text/plain'},
      ));
      expect(response.statusCode, 422);
    });

    test('skips non-text content types', () async {
      final guard = AiGuard(inputScanners: [_BlockScanner()]);
      Future<Response> inner(Request r) async =>
          Response.ok('ok', headers: {'content-type': 'image/png'});
      final handler = const Pipeline()
          .addMiddleware(guardMiddleware(guard))
          .addHandler(inner);

      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: 'binary',
        headers: {'content-type': 'image/png'},
      ));
      expect(response.statusCode, 200);
    });

    test('adds guard headers on pass', () async {
      final guard = AiGuard(outputScanners: [_PassScanner()]);
      Future<Response> inner(Request r) async =>
          Response.ok('ok', headers: {'content-type': 'text/plain'});
      final handler = const Pipeline()
          .addMiddleware(guardMiddleware(guard))
          .addHandler(inner);

      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: 'hello',
        headers: {'content-type': 'text/plain'},
      ));
      expect(response.headers['x-guard-blocked'], 'false');
      expect(response.headers['x-guard-findings-count'], '0');
    });
  });

  group('PolicyLoader', () {
    test('fromMap with scanner config', () {
      final guard = PolicyLoader.fromMap({
        'inputScanners': [
          {'type': 'pii', 'action': 'redact'}
        ],
      });
      expect(guard.inputScanners, hasLength(1));
    });

    test('fromMap with profile', () {
      final guard = PolicyLoader.fromMap({'profile': 'healthcare'});
      expect(guard.inputScanners, isNotEmpty);
    });

    test('fromMap with unknown profile throws', () {
      expect(
        () => PolicyLoader.fromMap({'profile': 'nonexistent'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromJson parses string', () {
      final guard =
          PolicyLoader.fromJson('{"inputScanners": [{"type": "pii"}]}');
      expect(guard.inputScanners, hasLength(1));
    });
  });
}
