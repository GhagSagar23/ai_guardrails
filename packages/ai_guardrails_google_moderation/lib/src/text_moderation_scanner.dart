import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:http/http.dart' as http;

class TextModerationScanner extends AsyncScanner {
  final String apiKey;
  final double threshold;
  final GuardAction action;
  final Set<String> categories;
  late final http.Client _client;

  TextModerationScanner({
    required this.apiKey,
    this.threshold = 0.7,
    this.action = GuardAction.block,
    this.categories = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'google_moderation';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    if (text.trim().isEmpty) return ScanResult.pass(name, text);

    final uri = Uri.parse(
      'https://language.googleapis.com/v2/documents:moderateText?key=$apiKey',
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'document': {'type': 'PLAIN_TEXT', 'content': text},
      }),
    );

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Google moderation API returned ${response.statusCode}: '
        '${response.body}',
        uri,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawCategories = body['moderationCategories'] as List<dynamic>? ?? [];

    final findings = <Finding>[];
    for (final entry in rawCategories) {
      final map = entry as Map<String, dynamic>;
      final categoryName = map['name'] as String;
      final confidence = (map['confidence'] as num).toDouble();
      if (confidence < threshold) continue;
      if (categories.isNotEmpty && !categories.contains(categoryName)) {
        continue;
      }
      final type =
          'google_moderation.${categoryName.toLowerCase().replaceAll(' ', '_')}';
      findings.add(Finding(type: type, confidence: confidence));
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    final reason = '${findings.length} moderation categor'
        '${findings.length == 1 ? 'y' : 'ies'} above threshold';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }

  void close() => _client.close();
}
