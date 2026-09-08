import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('HtmlValidator', () {
    test('passes allowed tags', () {
      final v = HtmlValidator();
      final result = v.scan('<p>Hello</p> <b>world</b>');
      expect(result.passed, isTrue);
    });

    test('blocks disallowed tags', () {
      final v = HtmlValidator();
      final result = v.scan('<script>alert(1)</script>');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'html_validator.tag'), isTrue);
    });

    test('blocks event handlers', () {
      final v = HtmlValidator();
      final result = v.scan('<img src="x" onerror="alert(1)">');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'html_validator.event_handler'),
          isTrue);
    });

    test('blocks javascript: URIs', () {
      final v = HtmlValidator();
      final result = v.scan('<a href="javascript:void(0)">click</a>');
      expect(result.passed, isFalse);
      expect(
          result.findings.any((f) => f.type == 'html_validator.javascript_uri'),
          isTrue);
    });

    test('blocks disallowed attributes', () {
      final v = HtmlValidator(allowedAttributes: {'href'});
      final result = v.scan('<a href="ok" style="color:red">test</a>');
      expect(result.passed, isFalse);
      expect(result.findings.any((f) => f.type == 'html_validator.attribute'),
          isTrue);
    });

    test('allows data- attributes', () {
      final v = HtmlValidator();
      final result = v.scan('<div data-id="123">test</div>');
      expect(result.passed, isTrue);
    });

    test('passes plain text', () {
      final v = HtmlValidator();
      final result = v.scan('Just plain text with no HTML');
      expect(result.passed, isTrue);
    });

    test('custom allowed tags', () {
      final v = HtmlValidator(allowedTags: {'p', 'custom'});
      expect(v.scan('<custom>ok</custom>').passed, isTrue);
      expect(v.scan('<div>not ok</div>').passed, isFalse);
    });

    test('warn mode', () {
      final v = HtmlValidator(action: GuardAction.warn);
      final result = v.scan('<script>bad</script>');
      expect(result.passed, isTrue);
      expect(result.hasFindings, isTrue);
    });

    test('registry builds', () {
      final s = ScannerRegistry.instance.build('html_validator');
      expect(s, isA<HtmlValidator>());
    });
  });
}
