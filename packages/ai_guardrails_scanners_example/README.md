<p align="center">
  <img src="https://raw.githubusercontent.com/GhagSagar23/ai_guardrails/master/icon/ai_guardrails.svg" width="120" alt="ai_guardrails logo" />
</p>

<h1 align="center">ai_guardrails_scanners_example</h1>

<p align="center">
  <strong>Example scanner plugin for <code>ai_guardrails</code></strong>
</p>

---

Reference implementation of the `ScannerPlugin` convention. Use this as a
template when building your own scanner pack.

## Naming convention

Scanner plugin packages follow the pattern:

```
ai_guardrails_scanners_<domain>
```

Examples: `ai_guardrails_scanners_medical`, `ai_guardrails_scanners_finance`,
`ai_guardrails_scanners_brand`.

## Creating a scanner plugin

### 1. Create the package

```bash
dart create -t package ai_guardrails_scanners_mydomain
cd ai_guardrails_scanners_mydomain
dart pub add ai_guardrails
```

### 2. Write your scanners

Each scanner implements `Scanner` (sync) or `AsyncScanner` (async):

```dart
import 'package:ai_guardrails/ai_guardrails.dart';

class MyScanner extends Scanner {
  @override
  String get name => 'my_scanner';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    // Your detection logic here
    return ScanResult.pass(name, text);
  }
}
```

### 3. Create the plugin class

Extend `ScannerPlugin` and register your scanners:

```dart
import 'package:ai_guardrails/ai_guardrails.dart';

class MyDomainPlugin extends ScannerPlugin {
  MyDomainPlugin();

  @override
  String get name => 'mydomain';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Scanners for my domain.';

  @override
  List<String> get scannerNames => const ['my_scanner'];

  @override
  void register(ScannerRegistry registry) {
    registry.register('my_scanner', (cfg) => MyScanner());
  }
}

final myDomainPlugin = MyDomainPlugin();
```

### 4. Export everything from the library file

```dart
library;

export 'src/my_domain_plugin.dart';
export 'src/my_scanner.dart';
```

### 5. Users install your plugin

```dart
import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:ai_guardrails_scanners_mydomain/ai_guardrails_scanners_mydomain.dart';

final hub = ScannerHub();
hub.install(myDomainPlugin);

// Now available by name:
final guard = AiGuard.fromConfig({
  'inputScanners': [{'type': 'my_scanner'}],
});
```

## Plugin checklist

- [ ] `name` is unique and descriptive
- [ ] `version` follows SemVer
- [ ] `scannerNames` matches exactly what `register()` registers
- [ ] Each scanner builds with an empty config (no required config keys)
- [ ] Tests cover each scanner independently
- [ ] Export the plugin class and a top-level instance

## This example

This package includes two demo scanners:

| Scanner | Name | Description |
| --- | --- | --- |
| `ProfanityScanner` | `profanity` | Keyword-based profanity detection |
| `WordCountScanner` | `word_count` | Blocks text exceeding a word limit |

## License

[Apache-2.0](https://github.com/GhagSagar23/ai_guardrails/blob/master/LICENSE) © GhagSagar23
