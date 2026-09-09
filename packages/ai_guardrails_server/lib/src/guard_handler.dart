import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// REST handler exposing [AiGuard] as HTTP endpoints.
///
/// Endpoints:
/// - `GET  /health` — health check
/// - `POST /v1/scan/input` — scan text through input pipeline
/// - `POST /v1/scan/output` — scan text through output pipeline
/// - `POST /v1/chat/completions` — OpenAI-compatible proxy
class GuardHandler {
  final AiGuard guard;
  final String? backendUrl;
  final http.Client _client;

  GuardHandler({
    required this.guard,
    this.backendUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Top-level shelf [Handler] that routes requests.
  Future<Response> call(Request request) async {
    final path = '/${request.url.path}';
    final method = request.method;

    if (method == 'GET' && path == '/health') return _health(request);
    if (method == 'POST' && path == '/v1/scan/input') {
      return _scanInput(request);
    }
    if (method == 'POST' && path == '/v1/scan/output') {
      return _scanOutput(request);
    }
    if (method == 'POST' && path == '/v1/chat/completions') {
      return _chatCompletions(request);
    }
    return Response.notFound(
        jsonEncode({
          'error': {'message': 'Not found', 'code': 'not_found'}
        }),
        headers: {'content-type': 'application/json'});
  }

  Response _health(Request request) => Response.ok(jsonEncode({'status': 'ok'}),
      headers: {'content-type': 'application/json'});

  Future<Response> _scanInput(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final text = json['text'] as String? ?? '';
    final results = await guard.scanInput(text);
    return _scanResponse(results);
  }

  Future<Response> _scanOutput(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final text = json['text'] as String? ?? '';
    final results = await guard.scanOutput(text);
    return _scanResponse(results);
  }

  Response _scanResponse(List<ScanResult> results) {
    final blocked = results.any((r) => !r.passed);
    final processedText = results.isNotEmpty ? results.last.text : '';
    return Response.ok(
        jsonEncode({
          'passed': !blocked,
          'processedText': processedText,
          'results': results.map(_resultToJson).toList(),
        }),
        headers: {
          'content-type': 'application/json',
          'x-guard-blocked': '$blocked',
          'x-guard-findings-count':
              '${results.fold<int>(0, (s, r) => s + r.findings.length)}',
        });
  }

  Future<Response> _chatCompletions(Request request) async {
    if (backendUrl == null || backendUrl!.isEmpty) {
      return Response(502,
          body: jsonEncode({
            'error': {
              'message':
                  'LLM_BACKEND_URL not configured — proxy mode unavailable',
              'type': 'configuration_error',
              'code': 'no_backend',
            }
          }),
          headers: {'content-type': 'application/json'});
    }

    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final messages = (json['messages'] as List?) ?? [];

    final userContent = _extractLastUserContent(messages);
    if (userContent.isEmpty) {
      return _forwardToBackend(body, request);
    }

    final outcome = await guard.run(
      input: userContent,
      llmCall: (sanitizedInput) async {
        final modifiedBody = _replaceLastUserContent(json, sanitizedInput);
        final backendResponse =
            await _forwardRaw(jsonEncode(modifiedBody), request);
        final backendJson = jsonDecode(backendResponse) as Map<String, dynamic>;
        return _extractAssistantContent(backendJson);
      },
    );

    if (outcome.blocked) {
      final stage =
          outcome.blockedStage == ScanStage.input ? 'input' : 'output';
      return Response(400,
          body: jsonEncode({
            'error': {
              'message':
                  'Blocked by guardrails ($stage): ${outcome.blockReason}',
              'type': 'guard_blocked',
              'code': '${stage}_blocked',
            }
          }),
          headers: {
            'content-type': 'application/json',
            'x-guard-blocked': 'true',
          });
    }

    final responseJson = {
      'id': 'chatcmpl-guard-${DateTime.now().millisecondsSinceEpoch}',
      'object': 'chat.completion',
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': outcome.output},
          'finish_reason': 'stop',
        }
      ],
    };

    final totalFindings = outcome.allFindings.length;
    return Response.ok(jsonEncode(responseJson), headers: {
      'content-type': 'application/json',
      'x-guard-blocked': 'false',
      'x-guard-findings-count': '$totalFindings',
    });
  }

  Future<Response> _forwardToBackend(String body, Request request) async {
    final response = await _forwardRaw(body, request);
    return Response.ok(response, headers: {'content-type': 'application/json'});
  }

  Future<String> _forwardRaw(String body, Request request) async {
    final uri = Uri.parse('$backendUrl/v1/chat/completions');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    final auth = request.headers['authorization'];
    if (auth != null) headers['authorization'] = auth;

    final response = await _client.post(uri, body: body, headers: headers);
    return response.body;
  }

  String _extractLastUserContent(List<dynamic> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i] as Map<String, dynamic>;
      if (msg['role'] == 'user') return msg['content'] as String? ?? '';
    }
    return '';
  }

  Map<String, dynamic> _replaceLastUserContent(
      Map<String, dynamic> original, String newContent) {
    final result = Map<String, dynamic>.from(original);
    final messages = (result['messages'] as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'user') {
        messages[i]['content'] = newContent;
        break;
      }
    }
    result['messages'] = messages;
    return result;
  }

  String _extractAssistantContent(Map<String, dynamic> json) {
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return '';
    final first = choices[0] as Map<String, dynamic>;
    final message = first['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }

  static Map<String, dynamic> _resultToJson(ScanResult r) => {
        'scanner': r.scanner,
        'passed': r.passed,
        'score': r.score,
        'reason': r.reason,
        'findings': r.findings
            .map((f) => {
                  'type': f.type,
                  'confidence': f.confidence,
                  'start': f.start,
                  'end': f.end,
                })
            .toList(),
      };

  void close() => _client.close();
}
