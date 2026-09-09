import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

class MockSpan implements GuardSpan {
  final String name;
  final Map<String, Object> attributes;
  final List<MockSpan> children = [];
  final List<Object> errors = [];
  bool ended = false;

  MockSpan(this.name, {Map<String, Object>? attributes})
      : attributes = {...?attributes};

  @override
  void setAttribute(String key, Object value) => attributes[key] = value;

  @override
  GuardSpan startChild(String name, {Map<String, Object>? attributes}) {
    final child = MockSpan(name, attributes: attributes);
    children.add(child);
    return child;
  }

  @override
  void recordError(Object error, {StackTrace? stackTrace}) => errors.add(error);

  @override
  void end() => ended = true;
}

class MockTracer implements GuardTracer {
  final List<MockSpan> spans = [];

  @override
  GuardSpan startSpan(String name, {Map<String, Object>? attributes}) {
    final span = MockSpan(name, attributes: attributes);
    spans.add(span);
    return span;
  }
}

class _BlockScanner extends Scanner {
  @override
  String get name => 'blocker';
  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.block(name, text,
          findings: [const Finding(type: 'blocker.test')], reason: 'blocked');
}

class _PassScanner extends Scanner {
  @override
  String get name => 'passer';
  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      ScanResult.pass(name, text);
}

class _ThrowScanner extends Scanner {
  @override
  String get name => 'thrower';
  @override
  Set<ScanStage> get stages => const {ScanStage.input};
  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) =>
      throw Exception('boom');
}

void main() {
  group('GuardSemantics', () {
    test('constants are non-empty strings', () {
      expect(GuardSemantics.scannerName, isNotEmpty);
      expect(GuardSemantics.scanStage, isNotEmpty);
      expect(GuardSemantics.scanResult, isNotEmpty);
      expect(GuardSemantics.findingCount, isNotEmpty);
      expect(GuardSemantics.blocked, isNotEmpty);
      expect(GuardSemantics.durationMs, isNotEmpty);
      expect(GuardSemantics.errorType, isNotEmpty);
      expect(GuardSemantics.toolName, isNotEmpty);
    });
  });

  group('AiGuard tracing', () {
    test('no tracer = no errors', () async {
      final guard = AiGuard(inputScanners: [_PassScanner()]);
      final outcome =
          await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      expect(outcome.blocked, false);
    });

    test('run creates root span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(inputScanners: [_PassScanner()], tracer: tracer);
      await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      expect(tracer.spans, hasLength(1));
      expect(tracer.spans.first.name, 'guard.run');
      expect(tracer.spans.first.ended, true);
    });

    test('run creates input and output stage child spans', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        outputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      final root = tracer.spans.first;
      expect(root.children, hasLength(2));
      expect(root.children[0].name, 'guard.input');
      expect(root.children[1].name, 'guard.output');
      expect(root.children[0].ended, true);
      expect(root.children[1].ended, true);
    });

    test('scanner child spans with attributes', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      final stageSpan = tracer.spans.first.children.first;
      expect(stageSpan.children, hasLength(1));
      final scanSpan = stageSpan.children.first;
      expect(scanSpan.name, 'scan');
      expect(scanSpan.attributes[GuardSemantics.scannerName], 'passer');
      expect(scanSpan.attributes[GuardSemantics.scanResult], 'pass');
      expect(scanSpan.attributes[GuardSemantics.findingCount], 0);
      expect(scanSpan.ended, true);
    });

    test('blocked sets attributes on root span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_BlockScanner()],
        tracer: tracer,
      );
      final outcome =
          await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      expect(outcome.blocked, true);
      final root = tracer.spans.first;
      expect(root.attributes[GuardSemantics.blocked], true);
      expect(root.attributes[GuardSemantics.blockReason], 'blocked');
      expect(root.ended, true);
    });

    test('blocked scanner records findings in scan span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_BlockScanner()],
        tracer: tracer,
      );
      await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      final scanSpan = tracer.spans.first.children.first.children.first;
      expect(scanSpan.attributes[GuardSemantics.scanResult], 'block');
      expect(scanSpan.attributes[GuardSemantics.findingCount], 1);
      expect(scanSpan.attributes[GuardSemantics.findingTypes], 'blocker.test');
    });

    test('scanner error records on span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_ThrowScanner()],
        failClosed: true,
        tracer: tracer,
      );
      await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      final scanSpan = tracer.spans.first.children.first.children.first;
      expect(scanSpan.errors, hasLength(1));
      expect(scanSpan.errors.first, isA<Exception>());
    });

    test('scanner error with failClosed=false skips', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_ThrowScanner()],
        failClosed: false,
        tracer: tracer,
      );
      final outcome =
          await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      expect(outcome.blocked, false);
      final scanSpan = tracer.spans.first.children.first.children.first;
      expect(scanSpan.errors, hasLength(1));
      expect(scanSpan.ended, true);
    });

    test('scanInput creates root stage span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.scanInput('hello');
      expect(tracer.spans, hasLength(1));
      expect(tracer.spans.first.name, 'guard.input');
    });

    test('scanOutput creates root stage span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        outputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.scanOutput('hello');
      expect(tracer.spans, hasLength(1));
      expect(tracer.spans.first.name, 'guard.output');
    });

    test('runToolOutputStage creates spans per tool', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.runToolOutputStage([
        const ToolOutput(toolName: 'calc', content: '42'),
        const ToolOutput(toolName: 'search', content: 'result'),
      ]);
      expect(tracer.spans, hasLength(2));
    });

    test('runRetrievalStage creates spans per chunk', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.runRetrievalStage(['chunk1', 'chunk2', 'chunk3']);
      expect(tracer.spans, hasLength(3));
    });

    test('success path sets blocked=false', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        outputScanners: [_PassScanner()],
        tracer: tracer,
      );
      await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      final root = tracer.spans.first;
      expect(root.attributes[GuardSemantics.blocked], false);
      expect(root.attributes.containsKey(GuardSemantics.durationMs), true);
    });

    test('output blocker ends root span', () async {
      final tracer = MockTracer();
      final guard = AiGuard(
        inputScanners: [_PassScanner()],
        outputScanners: [_BlockScanner()],
        tracer: tracer,
      );
      final outcome =
          await guard.run(input: 'hello', llmCall: (s) async => 'reply');
      expect(outcome.blocked, true);
      expect(outcome.blockedStage, ScanStage.output);
      final root = tracer.spans.first;
      expect(root.attributes[GuardSemantics.blocked], true);
      expect(root.ended, true);
    });
  });
}
