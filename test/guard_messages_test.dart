import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('GuardMessages', () {
    const msgs = GuardMessages();

    test('English message for pii', () {
      expect(msgs.message('pii'),
          'Personal information was detected and handled.');
    });

    test('Spanish message for pii', () {
      expect(msgs.message('pii', locale: 'es'),
          'Se detectó información personal y se gestionó.');
    });

    test('Japanese message for prompt_injection', () {
      expect(msgs.message('prompt_injection', locale: 'ja'),
          'プロンプトインジェクションの可能性が検出されました。');
    });

    test('fallback to English when locale missing', () {
      expect(msgs.message('pii', locale: 'xx'),
          'Personal information was detected and handled.');
    });

    test('fallback to generic when scanner unknown', () {
      expect(
          msgs.message('nonexistent_scanner'), 'A safety issue was detected.');
    });

    test('custom messages override built-in', () {
      final custom = GuardMessages(customMessages: {
        'en': {'pii': 'Custom PII message.'}
      });
      expect(custom.message('pii'), 'Custom PII message.');
    });

    test('custom messages per locale', () {
      final custom = GuardMessages(customMessages: {
        'es': {'pii': 'Mensaje personalizado.'}
      });
      expect(custom.message('pii', locale: 'es'), 'Mensaje personalizado.');
      // English still uses built-in
      expect(msgs.message('pii'),
          'Personal information was detected and handled.');
    });

    test('availableLocales returns all 11', () {
      final locales = GuardMessages.availableLocales;
      expect(
          locales,
          containsAll([
            'en',
            'es',
            'pt',
            'fr',
            'de',
            'it',
            'ja',
            'ko',
            'zh',
            'ar',
            'hi'
          ]));
      expect(locales, hasLength(11));
    });

    test('supportedScanners includes core scanners', () {
      final scanners = GuardMessages.supportedScanners;
      expect(
          scanners,
          containsAll([
            'pii',
            'secret',
            'prompt_injection',
            'url',
            'code_exec',
            'hallucination',
            'policy_rule'
          ]));
    });

    test('all locales have pii message', () {
      for (final locale in GuardMessages.availableLocales) {
        expect(msgs.message('pii', locale: locale),
            isNot('A safety issue was detected.'),
            reason: 'locale $locale missing pii message');
      }
    });

    test('all scanners have English message', () {
      for (final scanner in GuardMessages.supportedScanners) {
        expect(msgs.message(scanner), isNot('A safety issue was detected.'),
            reason: 'scanner $scanner missing English message');
      }
    });

    test('default locale is English', () {
      expect(msgs.message('secret'),
          'A potential secret or credential was detected.');
    });

    test('const constructor works', () {
      const m = GuardMessages();
      expect(m.message('pii'), isNotEmpty);
    });
  });

  group('ScanResultMessages extension', () {
    test('userMessage returns English by default', () {
      const result = ScanResult.block('pii', 'text',
          findings: [Finding(type: 'pii.email')]);
      expect(result.userMessage(),
          'Personal information was detected and handled.');
    });

    test('userMessage with locale', () {
      const result = ScanResult.block('secret', 'text',
          findings: [Finding(type: 'secret.aws')]);
      expect(result.userMessage(locale: 'de'),
          'Ein mögliches Geheimnis oder Zugangsdaten wurden erkannt.');
    });

    test('userMessage with custom GuardMessages', () {
      const result = ScanResult.warn('pii', 'text',
          findings: [Finding(type: 'pii.phone')]);
      final custom = GuardMessages(customMessages: {
        'en': {'pii': 'Phone removed.'}
      });
      expect(result.userMessage(messages: custom), 'Phone removed.');
    });
  });
}
