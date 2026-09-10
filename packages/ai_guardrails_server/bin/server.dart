import 'dart:io';

import 'package:ai_guardrails_server/ai_guardrails_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

void main(List<String> args) async {
  final configPath = args.isNotEmpty ? args[0] : 'config.json';
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final backendUrl = Platform.environment['LLM_BACKEND_URL'] ?? '';

  final guard = PolicyLoader.fromFile(configPath);
  final handler = GuardHandler(guard: guard, backendUrl: backendUrl);

  final pipeline =
      const Pipeline().addMiddleware(logRequests()).addHandler(handler.call);

  final server = await io.serve(pipeline, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('Guard server on http://${server.address.host}:${server.port}');
  // ignore: avoid_print
  print(
      'Backend: ${backendUrl.isEmpty ? "(none — proxy disabled)" : backendUrl}');
}
