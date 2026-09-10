import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:http/http.dart' as http;

class PerspectiveScanner extends AsyncScanner {
  final String apiKey;
  final double threshold;
  final GuardAction action;
  final Set<String> attributes;
  late final http.Client _client;

  PerspectiveScanner({
    required this.apiKey,
    this.threshold = 0.7,
    this.action = GuardAction.block,
    this.attributes = const {'TOXICITY'},
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'perspective';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  Future<ScanResult> scanAsync(String text,
      {ScanStage stage = ScanStage.input}) async {
    if (text.trim().isEmpty) return ScanResult.pass(name, text);

    final uri = Uri.parse(
      'https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze'
      '?key=$apiKey',
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'comment': {'text': text},
        'requestedAttributes': {for (final attr in attributes) attr: {}},
      }),
    );

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Perspective API returned ${response.statusCode}: ${response.body}',
        uri,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final scores = body['attributeScores'] as Map<String, dynamic>? ?? {};

    final findings = <Finding>[];
    for (final attr in attributes) {
      final attrScore = scores[attr] as Map<String, dynamic>?;
      if (attrScore == null) continue;
      final summary = attrScore['summaryScore'] as Map<String, dynamic>;
      final value = (summary['value'] as num).toDouble();
      if (value < threshold) continue;
      findings.add(
        Finding(type: 'perspective.${attr.toLowerCase()}', confidence: value),
      );
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    final reason = '${findings.length} attribute'
        '${findings.length == 1 ? '' : 's'} above threshold';
    if (action == GuardAction.warn) {
      return ScanResult.warn(name, text, findings: findings, reason: reason);
    }
    return ScanResult.block(name, text, findings: findings, reason: reason);
  }

  void close() => _client.close();
}
