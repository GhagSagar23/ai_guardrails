import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_langchain/ai_guardrails_langchain.dart';
import 'package:test/test.dart';

void main() {
  group('GuardrailsTool', () {
    test('returns pass for clean text', () async {
      final tool = GuardrailsTool(
          guard: AiGuard(inputScanners: [
        SecretScanner(),
      ]));

      final result = await tool.invoke('Hello world');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['blocked'], false);
      expect(json['finding_count'], 0);
      expect(json['findings'], isEmpty);
    });

    test('detects secret in input', () async {
      final tool = GuardrailsTool(
          guard: AiGuard(inputScanners: [
        SecretScanner(),
      ]));

      final result = await tool.invoke('key: AKIAIOSFODNN7EXAMPLE');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['blocked'], true);
      expect(json['finding_count'], greaterThan(0));
      expect(json['block_reason'], isNotNull);

      final findings = json['findings'] as List;
      expect(findings.first['scanner'], 'secret');
    });

    test('scans as output stage when configured', () async {
      final tool = GuardrailsTool(
        guard: AiGuard(outputScanners: [SecretScanner()]),
        scanStage: ScanStage.output,
      );

      final result = await tool.invoke('key: AKIAIOSFODNN7EXAMPLE');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['blocked'], true);
    });

    test('default name and description', () {
      final tool = GuardrailsTool(guard: AiGuard());
      expect(tool.name, 'guardrails_scan');
      expect(tool.description, contains('safety'));
    });

    test('custom name and description', () {
      final tool = GuardrailsTool(
        guard: AiGuard(),
        name: 'pii_check',
        description: 'Check for PII only.',
      );
      expect(tool.name, 'pii_check');
      expect(tool.description, 'Check for PII only.');
    });

    test('inputJsonSchema has input field', () {
      final tool = GuardrailsTool(guard: AiGuard());
      final schema = tool.inputJsonSchema;
      expect(schema['type'], 'object');
      final props = schema['properties'] as Map<String, dynamic>;
      expect(props.containsKey('input'), true);
    });

    test('getInputFromJson extracts input', () {
      final tool = GuardrailsTool(guard: AiGuard());
      final input = tool.getInputFromJson({'input': 'test text'});
      expect(input, 'test text');
    });

    test('multiple findings from PII scanner', () async {
      final tool = GuardrailsTool(
        guard: AiGuard(inputScanners: [
          PiiScanner(action: GuardAction.warn),
        ]),
      );

      final result = await tool.invoke(
        'Call 555-123-4567 or email test@example.com',
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['blocked'], false);
      expect(json['finding_count'], greaterThanOrEqualTo(2));
    });

    test('returns scanner_count', () async {
      final tool = GuardrailsTool(
          guard: AiGuard(inputScanners: [
        SecretScanner(),
        PiiScanner(action: GuardAction.warn),
      ]));

      final result = await tool.invoke('Hello world');
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['scanner_count'], 2);
    });
  });
}
