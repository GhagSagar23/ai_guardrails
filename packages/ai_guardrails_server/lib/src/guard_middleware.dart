import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:shelf/shelf.dart';

/// Shelf [Middleware] that scans request and response bodies through [AiGuard].
///
/// Only scans `application/json` and `text/*` content types. Binary or
/// form-data requests pass through unscanned.
///
/// ```dart
/// final guard = AiGuard(inputScanners: [PiiScanner()]);
/// final handler = const Pipeline()
///     .addMiddleware(guardMiddleware(guard))
///     .addHandler(myApp);
/// ```
Middleware guardMiddleware(AiGuard guard) {
  return (Handler innerHandler) {
    return (Request request) async {
      final contentType = request.headers['content-type'] ?? '';
      final scannable =
          contentType.contains('json') || contentType.startsWith('text/');

      if (!scannable) return innerHandler(request);

      final body = await request.readAsString();
      if (body.isEmpty) return innerHandler(request);

      final inputResults = await guard.scanInput(body);
      final inputBlocked = inputResults.any((r) => !r.passed);
      if (inputBlocked) {
        final reason = inputResults
            .where((r) => !r.passed)
            .map((r) => r.reason ?? r.scanner)
            .join('; ');
        return Response(400,
            body: jsonEncode({
              'error': {
                'message': 'Input blocked by guardrails: $reason',
                'type': 'guard_blocked',
                'code': 'input_blocked',
              }
            }),
            headers: {
              'content-type': 'application/json',
              'x-guard-blocked': 'true',
            });
      }

      final rebuilt = Request(
        request.method,
        request.requestedUri,
        body: body,
        headers: request.headers,
        context: request.context,
      );
      final response = await innerHandler(rebuilt);

      final responseType = response.headers['content-type'] ?? '';
      final scannableResponse =
          responseType.contains('json') || responseType.startsWith('text/');
      if (!scannableResponse) return response;

      final responseBody = await response.readAsString();
      if (responseBody.isEmpty) return response;

      final outputResults = await guard.scanOutput(responseBody);
      final outputBlocked = outputResults.any((r) => !r.passed);
      if (outputBlocked) {
        final reason = outputResults
            .where((r) => !r.passed)
            .map((r) => r.reason ?? r.scanner)
            .join('; ');
        return Response(422,
            body: jsonEncode({
              'error': {
                'message': 'Output blocked by guardrails: $reason',
                'type': 'guard_blocked',
                'code': 'output_blocked',
              }
            }),
            headers: {
              'content-type': 'application/json',
              'x-guard-blocked': 'true',
            });
      }

      final findingCount =
          outputResults.fold<int>(0, (sum, r) => sum + r.findings.length);
      return Response(response.statusCode, body: responseBody, headers: {
        ...response.headers,
        'x-guard-blocked': 'false',
        'x-guard-findings-count': '$findingCount',
      });
    };
  };
}
