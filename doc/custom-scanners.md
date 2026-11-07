# Custom scanners

Back to [README](../README.md).

---

## Synchronous Scanner

The `Scanner` contract is tiny — pure and synchronous, no I/O:

```dart
class UppercaseYell implements Scanner {
  @override
  String get name => 'uppercase_yell';

  @override
  Set<ScanStage> get stages => {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final yelling = text == text.toUpperCase() && text.length > 20;
    if (!yelling) return ScanResult.pass(name, text);
    return ScanResult.block(name, text, reason: 'model is shouting',
      findings: [const Finding(type: 'yell.uppercase')]);
  }
}
```

## AsyncScanner

For scanners that need async work (model inference, I/O), implement `AsyncScanner`:

```dart
class MyMlScanner implements AsyncScanner {
  @override
  String get name => 'my_ml';

  @override
  Set<ScanStage> get stages => {ScanStage.input};

  @override
  Future<ScanResult> scanAsync(String text, {ScanStage stage = ScanStage.input}) async {
    final score = await _runModel(text);
    if (score < 0.8) return ScanResult.pass(name, text);
    return ScanResult.block(name, text, score: score, reason: 'ML classifier triggered',
      findings: [Finding(type: 'ml.detected', confidence: score)]);
  }
}
```

Drop either type into `inputScanners` / `outputScanners` — `AiGuard` handles both.
