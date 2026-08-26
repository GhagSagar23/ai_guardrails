import 'dart:convert';

import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('ToolCall', () {
    test('fromJson parses name and arguments', () {
      final tc = ToolCall.fromJson({
        'name': 'search',
        'arguments': {'q': 'dart'},
      });
      expect(tc.name, 'search');
      expect(tc.arguments, {'q': 'dart'});
    });

    test('fromJson defaults arguments to empty map', () {
      final tc = ToolCall.fromJson({'name': 'ping'});
      expect(tc.arguments, isEmpty);
    });

    test('fromJson throws on missing name', () {
      expect(
        () => ToolCall.fromJson({'arguments': {}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws on empty name', () {
      expect(
        () => ToolCall.fromJson({'name': '', 'arguments': {}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson round-trips', () {
      final tc = ToolCall(name: 'get_weather', arguments: {'city': 'Tokyo'});
      final json = tc.toJson();
      final back = ToolCall.fromJson(json);
      expect(back.name, tc.name);
      expect(back.arguments, tc.arguments);
    });
  });

  group('ToolCallScanner', () {
    test('passes valid tool with no allow/deny lists', () {
      final s = ToolCallScanner();
      final r = s.scan(jsonEncode({'name': 'search', 'arguments': {}}));
      expect(r.passed, isTrue);
      expect(r.findings, isEmpty);
    });

    test('passes tool in allowlist', () {
      final s = ToolCallScanner(allowedTools: {'search', 'get_weather'});
      final r = s.scan(jsonEncode({'name': 'search', 'arguments': {}}));
      expect(r.passed, isTrue);
    });

    test('blocks tool not in allowlist', () {
      final s = ToolCallScanner(allowedTools: {'search'});
      final r = s.scan(jsonEncode({'name': 'delete_all', 'arguments': {}}));
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'tool_call.unknown_name');
      expect(r.findings.first.match, 'delete_all');
    });

    test('blocks tool in denylist', () {
      final s = ToolCallScanner(deniedTools: {'rm_rf', 'drop_table'});
      final r = s.scan(jsonEncode({'name': 'rm_rf', 'arguments': {}}));
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'tool_call.denied_name');
    });

    test('denylist overrides allowlist', () {
      final s = ToolCallScanner(
        allowedTools: {'search', 'execute'},
        deniedTools: {'execute'},
      );
      final r = s.scan(jsonEncode({'name': 'execute', 'arguments': {}}));
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'tool_call.denied_name');
    });

    test('handles JSON array of tool calls', () {
      final s = ToolCallScanner(allowedTools: {'search'});
      final r = s.scan(
        jsonEncode([
          {'name': 'search', 'arguments': {}},
          {'name': 'hack', 'arguments': {}},
        ]),
      );
      expect(r.passed, isFalse);
      expect(r.findings.length, 1);
      expect(r.findings.first.match, 'hack');
    });

    test('blocks malformed JSON', () {
      final s = ToolCallScanner();
      final r = s.scan('not json at all');
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'tool_call.malformed');
    });

    test('blocks JSON missing name field', () {
      final s = ToolCallScanner();
      final r = s.scan(
        jsonEncode({
          'arguments': {'a': 1},
        }),
      );
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'tool_call.malformed');
    });

    test('passes empty array', () {
      final s = ToolCallScanner(allowedTools: {'search'});
      final r = s.scan('[]');
      expect(r.passed, isTrue);
    });

    test('passes empty string', () {
      final s = ToolCallScanner();
      final r = s.scan('');
      expect(r.passed, isTrue);
    });

    test('warn action records findings without blocking', () {
      final s = ToolCallScanner(
        allowedTools: {'search'},
        action: GuardAction.warn,
      );
      final r = s.scan(jsonEncode({'name': 'hack', 'arguments': {}}));
      expect(r.passed, isTrue);
      expect(r.findings, isNotEmpty);
      expect(r.findings.first.type, 'tool_call.unknown_name');
    });

    test('multiple violations in array', () {
      final s = ToolCallScanner(
        allowedTools: {'search'},
        deniedTools: {'rm_rf'},
      );
      final r = s.scan(
        jsonEncode([
          {'name': 'rm_rf', 'arguments': {}},
          {'name': 'search', 'arguments': {}},
          {'name': 'unknown_tool', 'arguments': {}},
        ]),
      );
      expect(r.passed, isFalse);
      expect(r.findings.length, 2);
      expect(r.findings[0].type, 'tool_call.denied_name');
      expect(r.findings[1].type, 'tool_call.unknown_name');
    });

    test('name is tool_call', () {
      expect(ToolCallScanner().name, 'tool_call');
    });

    test('stages is output only', () {
      expect(ToolCallScanner().stages, {ScanStage.output});
    });

    test('parseToolCalls static helper works', () {
      final calls = ToolCallScanner.parseToolCalls(
        jsonEncode([
          {
            'name': 'a',
            'arguments': {'x': 1},
          },
          {'name': 'b'},
        ]),
      );
      expect(calls.length, 2);
      expect(calls[0].name, 'a');
      expect(calls[1].arguments, isEmpty);
    });
  });

  group('ToolCallScanner — argument schema validation', () {
    final schemas = <String, Map<String, dynamic>>{
      'search': {
        'type': 'object',
        'required': ['query'],
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'number'},
        },
      },
      'send_email': {
        'type': 'object',
        'required': ['to', 'body'],
        'properties': {
          'to': {'type': 'string'},
          'body': {'type': 'string'},
          'cc': {'type': 'array'},
        },
      },
    };

    test('passes when args match schema', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'search',
        'arguments': {'query': 'dart guardrails', 'limit': 10},
      }));
      expect(r.passed, isTrue);
      expect(r.findings, isEmpty);
    });

    test('blocks on missing required argument', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'search',
        'arguments': {'limit': 5},
      }));
      expect(r.passed, isFalse);
      expect(r.findings.length, 1);
      expect(r.findings.first.type, 'tool_call.arg_missing_required');
      expect(r.findings.first.match, 'search.query');
    });

    test('blocks on type mismatch', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'search',
        'arguments': {'query': 123, 'limit': 10},
      }));
      expect(r.passed, isFalse);
      expect(r.findings.first.type, 'tool_call.arg_type_mismatch');
      expect(r.findings.first.match, 'search.query');
    });

    test('multiple schema violations', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'send_email',
        'arguments': {'cc': 'not-an-array'},
      }));
      expect(r.passed, isFalse);
      final types = r.findings.map((f) => f.type).toSet();
      expect(types, contains('tool_call.arg_missing_required'));
      expect(types, contains('tool_call.arg_type_mismatch'));
    });

    test('skips validation when tool has no schema', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'unknown_tool',
        'arguments': {'anything': 'goes'},
      }));
      expect(r.passed, isTrue);
    });

    test('skips validation when toolSchemas is null', () {
      final s = ToolCallScanner();
      final r = s.scan(jsonEncode({
        'name': 'search',
        'arguments': {},
      }));
      expect(r.passed, isTrue);
    });

    test('array type validates correctly', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'send_email',
        'arguments': {
          'to': 'a@b.com',
          'body': 'hello',
          'cc': ['x@y.com'],
        },
      }));
      expect(r.passed, isTrue);
    });

    test('boolean and object types validate', () {
      final s = ToolCallScanner(
        toolSchemas: {
          'configure': {
            'type': 'object',
            'properties': {
              'enabled': {'type': 'boolean'},
              'settings': {'type': 'object'},
            },
          },
        },
      );
      final r = s.scan(jsonEncode({
        'name': 'configure',
        'arguments': {'enabled': 'yes', 'settings': 'nope'},
      }));
      expect(r.passed, isFalse);
      expect(r.findings.length, 2);
    });

    test('integer type accepts num values', () {
      final s = ToolCallScanner(
        toolSchemas: {
          'count': {
            'type': 'object',
            'properties': {
              'n': {'type': 'integer'},
            },
          },
        },
      );
      final r = s.scan(jsonEncode({
        'name': 'count',
        'arguments': {'n': 42},
      }));
      expect(r.passed, isTrue);
    });

    test('schema + name violations combined', () {
      final s = ToolCallScanner(
        allowedTools: {'search'},
        toolSchemas: schemas,
      );
      final r = s.scan(jsonEncode([
        {
          'name': 'search',
          'arguments': {'limit': 'not-a-number'},
        },
        {
          'name': 'bad_tool',
          'arguments': {},
        },
      ]));
      expect(r.passed, isFalse);
      final types = r.findings.map((f) => f.type).toSet();
      expect(types, contains('tool_call.arg_missing_required'));
      expect(types, contains('tool_call.arg_type_mismatch'));
      expect(types, contains('tool_call.unknown_name'));
    });

    test('warn mode passes with schema findings', () {
      final s = ToolCallScanner(
        toolSchemas: schemas,
        action: GuardAction.warn,
      );
      final r = s.scan(jsonEncode({
        'name': 'search',
        'arguments': {'limit': 5},
      }));
      expect(r.passed, isTrue);
      expect(r.findings, isNotEmpty);
      expect(r.findings.first.type, 'tool_call.arg_missing_required');
    });

    test('extra args not in schema pass through', () {
      final s = ToolCallScanner(toolSchemas: schemas);
      final r = s.scan(jsonEncode({
        'name': 'search',
        'arguments': {'query': 'test', 'bonus': 42},
      }));
      expect(r.passed, isTrue);
    });
  });
}
