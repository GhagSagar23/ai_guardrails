import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:flutter_demo/providers/guard_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional scanners are off by default and on when enabled', () async {
    const ja = 'これは日本語の長い文章です。テストのために書かれています。';
    final off = await GuardConfig.chatGuard().scanInput(ja);
    expect(off.any((r) => r.scanner == 'language_detection'), isFalse);

    final on = await GuardConfig.chatGuard(
      enabled: GuardConfig.optionalScanners.keys.toSet(),
      relevance: RelevanceScanner(),
    ).scanInput(ja);
    final lang = on.firstWhere((r) => r.scanner == 'language_detection');
    expect(lang.passed, isFalse);
    expect(on.any((r) => r.scanner == 'toxicity'), isTrue);
  });

  test('relevance flags off-topic output', () async {
    final rel = RelevanceScanner(referenceText: 'How do I reset my password?');
    final out = await GuardConfig.chatGuard(
      enabled: {'relevance'},
      relevance: rel,
    ).scanOutput('Bananas are rich in potassium and grow in tropical areas.');
    expect(out.firstWhere((r) => r.scanner == 'relevance').hasFindings, isTrue);
  });
}
