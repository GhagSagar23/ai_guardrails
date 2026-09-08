import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('ToolOutputScanner', () {
    late ToolOutputScanner scanner;

    setUp(() {
      scanner = ToolOutputScanner();
    });

    test('clean text passes', () {
      final r = scanner.scan('The weather in London is 15°C and cloudy.');
      expect(r.passed, isTrue);
      expect(r.findings, isEmpty);
    });

    test('empty text passes', () {
      final r = scanner.scan('');
      expect(r.passed, isTrue);
    });

    group('XSS detection', () {
      test('detects script tags', () {
        final r = scanner.scan('<script>alert("xss")</script>');
        expect(r.passed, isFalse);
        expect(r.findings.any((f) => f.type == 'tool_output.xss'), isTrue);
      });

      test('detects javascript: URIs', () {
        final r = scanner.scan('Click <a href="javascript:alert(1)">here</a>');
        expect(r.passed, isFalse);
        expect(r.findings.any((f) => f.type == 'tool_output.xss'), isTrue);
      });

      test('detects event handlers', () {
        final r = scanner.scan('<img src=x onerror="alert(1)">');
        expect(r.passed, isFalse);
        expect(r.findings.any((f) => f.type == 'tool_output.xss'), isTrue);
      });

      test('detects iframe tags', () {
        final r = scanner.scan('<iframe src="http://evil.com"></iframe>');
        expect(r.passed, isFalse);
      });

      test('detects object tags', () {
        final r = scanner.scan('<object data="payload.swf"></object>');
        expect(r.passed, isFalse);
      });

      test('detects embed tags', () {
        final r = scanner.scan('<embed src="payload.swf">');
        expect(r.passed, isFalse);
      });

      test('detects SVG with event handlers', () {
        final r = scanner.scan('<svg onload="alert(1)">');
        expect(r.passed, isFalse);
      });

      test('detects CSS expression', () {
        final r = scanner.scan('div { background: expression(alert("xss")) }');
        expect(r.passed, isFalse);
      });
    });

    group('template injection detection', () {
      test('detects Jinja control tags', () {
        final r = scanner.scan('{% if admin %}secret{% endif %}');
        expect(r.passed, isFalse);
        expect(
            r.findings.any((f) => f.type == 'tool_output.template_injection'),
            isTrue);
      });

      test('detects ERB tags', () {
        final r = scanner.scan('<%= system("id") %>');
        expect(r.passed, isFalse);
      });

      test('detects SSTI config access', () {
        final r = scanner.scan('{{ config.SECRET_KEY }}');
        expect(r.passed, isFalse);
      });

      test('detects SSTI request access', () {
        final r = scanner.scan('{{ request.environ }}');
        expect(r.passed, isFalse);
      });

      test('detects Python dunder SSTI', () {
        final r = scanner.scan("''.__class__.__mro__[1].__subclasses__()");
        expect(r.passed, isFalse);
      });

      test('detects FreeMarker tags', () {
        final r = scanner.scan('<#assign ex="freemarker.template.utility">');
        expect(r.passed, isFalse);
      });
    });

    group('path traversal detection', () {
      test('detects ../ sequences', () {
        final r = scanner.scan('file: ../../etc/passwd');
        expect(r.passed, isFalse);
        expect(r.findings.any((f) => f.type == 'tool_output.path_traversal'),
            isTrue);
      });

      test('detects ..\\ sequences', () {
        final r = scanner.scan(r'path: ..\..\windows\system32');
        expect(r.passed, isFalse);
      });

      test('detects URL-encoded traversal', () {
        final r = scanner.scan('%2e%2e%2fetc/passwd');
        expect(r.passed, isFalse);
      });

      test('detects null bytes', () {
        final r = scanner.scan('file.php%00.jpg');
        expect(r.passed, isFalse);
      });
    });

    group('SSRF detection', () {
      test('detects cloud metadata endpoint', () {
        final r = scanner.scan('curl http://169.254.169.254/latest/meta-data/');
        expect(r.passed, isFalse);
        expect(r.findings.any((f) => f.type == 'tool_output.ssrf'), isTrue);
      });

      test('detects file:// protocol', () {
        final r = scanner.scan('file:///etc/passwd');
        expect(r.passed, isFalse);
      });

      test('detects gopher:// protocol', () {
        final r = scanner.scan('gopher://evil.com/payload');
        expect(r.passed, isFalse);
      });
    });

    group('JSON extraction', () {
      test('scans string values inside JSON objects', () {
        final json = jsonEncode({
          'result': '<script>alert(1)</script>',
          'status': 'ok',
        });
        final r = scanner.scan(json);
        expect(r.passed, isFalse);
        expect(r.findings.any((f) => f.type == 'tool_output.xss'), isTrue);
      });

      test('scans nested JSON values', () {
        final json = jsonEncode({
          'data': {
            'items': [
              {'html': '<iframe src="evil">'}
            ]
          }
        });
        final r = scanner.scan(json);
        expect(r.passed, isFalse);
      });

      test('clean JSON passes', () {
        final json = jsonEncode({
          'name': 'John Doe',
          'age': 30,
          'active': true,
        });
        final r = scanner.scan(json);
        expect(r.passed, isTrue);
      });

      test('JSON array with attack in one element', () {
        final json = jsonEncode([
          'safe text',
          '../../etc/shadow',
          'also safe',
        ]);
        final r = scanner.scan(json);
        expect(r.passed, isFalse);
      });
    });

    group('configuration', () {
      test('warn action does not block', () {
        final s = ToolOutputScanner(action: GuardAction.warn);
        final r = s.scan('<script>alert(1)</script>');
        expect(r.passed, isTrue);
        expect(r.findings, isNotEmpty);
      });

      test('category filtering', () {
        final xssOnly = ToolOutputScanner(
          categories: {ToolOutputCategory.xss},
        );
        final r = xssOnly.scan('../../etc/passwd');
        expect(r.passed, isTrue);
      });

      test('supports both input and output stages', () {
        expect(scanner.stages, contains(ScanStage.input));
        expect(scanner.stages, contains(ScanStage.output));
      });

      test('name is tool_output', () {
        expect(scanner.name, 'tool_output');
      });
    });

    group('registry', () {
      test('registered as tool_output', () {
        expect(ScannerRegistry.instance.has('tool_output'), isTrue);
      });

      test('builds from registry', () {
        final s = ScannerRegistry.instance.build('tool_output');
        expect(s, isA<ToolOutputScanner>());
      });

      test('builds with category filter from registry', () {
        final s = ScannerRegistry.instance.build('tool_output', {
          'categories': ['xss', 'ssrf'],
          'action': 'warn',
        });
        expect(s, isA<ToolOutputScanner>());
      });

      test('fromConfig builds tool_output', () {
        final guard = AiGuard.fromConfig({
          'inputScanners': [
            {'type': 'tool_output', 'action': 'warn'},
          ],
        });
        expect(guard.inputScanners, hasLength(1));
        expect(guard.inputScanners.first, isA<ToolOutputScanner>());
      });
    });

    group('runToolOutputStage', () {
      test('scans tool outputs through input scanners', () async {
        final guard = AiGuard(
          inputScanners: [ToolOutputScanner()],
        );
        final result = await guard.runToolOutputStage([
          const ToolOutput(
              toolName: 'web_search', content: 'Safe search result'),
          ToolOutput(
              toolName: 'fetch_html', content: '<script>alert("xss")</script>'),
          const ToolOutput(toolName: 'db_query', content: 'Normal db result'),
        ]);

        expect(result.safe, hasLength(2));
        expect(result.blocked, hasLength(1));
        expect(result.blocked.first.toolName, 'fetch_html');
      });

      test('empty outputs returns empty result', () async {
        final guard = AiGuard(inputScanners: [ToolOutputScanner()]);
        final result = await guard.runToolOutputStage([]);
        expect(result.scans, isEmpty);
        expect(result.safe, isEmpty);
        expect(result.blocked, isEmpty);
        expect(result.allFindings, isEmpty);
      });

      test('all safe outputs', () async {
        final guard = AiGuard(inputScanners: [ToolOutputScanner()]);
        final result = await guard.runToolOutputStage([
          const ToolOutput(toolName: 'a', content: 'safe'),
          const ToolOutput(toolName: 'b', content: 'also safe'),
        ]);
        expect(result.safe, hasLength(2));
        expect(result.blocked, isEmpty);
      });

      test('all blocked outputs', () async {
        final guard = AiGuard(inputScanners: [ToolOutputScanner()]);
        final result = await guard.runToolOutputStage([
          const ToolOutput(toolName: 'a', content: '<script>bad</script>'),
          const ToolOutput(toolName: 'b', content: '../../etc/passwd'),
        ]);
        expect(result.safe, isEmpty);
        expect(result.blocked, hasLength(2));
      });

      test('preserves tool name in scan results', () async {
        final guard = AiGuard(inputScanners: [ToolOutputScanner()]);
        final result = await guard.runToolOutputStage([
          const ToolOutput(toolName: 'my_tool', content: '<iframe src="x">'),
        ]);
        expect(result.blocked.first.toolName, 'my_tool');
        expect(result.blocked.first.blockReason, isNotNull);
      });

      test('allFindings aggregates across all scans', () async {
        final guard = AiGuard(inputScanners: [ToolOutputScanner()]);
        final result = await guard.runToolOutputStage([
          const ToolOutput(toolName: 'a', content: '<script>x</script>'),
          const ToolOutput(toolName: 'b', content: '../../secret'),
        ]);
        expect(result.allFindings.length, greaterThanOrEqualTo(2));
      });
    });
  });
}
