import '../scanner.dart';

/// Categories of dangerous code patterns.
enum CodeCategory { shell, sql, injection, filesystem }

/// Pattern group: a regex and the finding type it produces.
class CodePattern {
  final CodeCategory category;
  final String type;
  final RegExp regex;
  const CodePattern(this.category, this.type, this.regex);
}

/// Detects dangerous patterns in generated code: shell commands, SQL
/// destruction, code injection via eval/exec, and filesystem deletion.
///
/// For code-generation LLM apps where the output might be executed.
class CodeExecutionScanner implements Scanner {
  final GuardAction action;

  /// Categories to check. Default: all.
  final Set<CodeCategory> categories;

  CodeExecutionScanner({
    this.action = GuardAction.block,
    this.categories = const {
      CodeCategory.shell,
      CodeCategory.sql,
      CodeCategory.injection,
      CodeCategory.filesystem,
    },
  });

  @override
  String get name => 'code_exec';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  static final patterns = <CodePattern>[
    // Shell
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\brm\s+-[rf]{1,2}\b', caseSensitive: false)),
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\brm\s+-[rf]*\s+/', caseSensitive: false)),
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\bchmod\s+777\b', caseSensitive: false)),
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\bcurl\b[^|]*\|\s*(?:sh|bash)\b', caseSensitive: false)),
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\bwget\b[^|]*\|\s*(?:sh|bash)\b', caseSensitive: false)),
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\bmkfs\b', caseSensitive: false)),
    CodePattern(CodeCategory.shell, 'code_exec.shell',
        RegExp(r'\bdd\s+if=', caseSensitive: false)),

    // SQL
    CodePattern(CodeCategory.sql, 'code_exec.sql',
        RegExp(r'\bDROP\s+(?:TABLE|DATABASE)\b', caseSensitive: false)),
    CodePattern(CodeCategory.sql, 'code_exec.sql',
        RegExp(r'\bTRUNCATE\s+TABLE\b', caseSensitive: false)),
    CodePattern(CodeCategory.sql, 'code_exec.sql',
        RegExp(r'\bDELETE\s+FROM\s+\S+\s*;', caseSensitive: false)),
    CodePattern(CodeCategory.sql, 'code_exec.sql',
        RegExp(r';\s*--\s*', caseSensitive: false)),

    // Code injection
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\beval\s*\(', caseSensitive: false)),
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\bexec\s*\(', caseSensitive: false)),
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\bos\.system\s*\(', caseSensitive: false)),
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\bsubprocess\.(?:call|run|Popen)\s*\(', caseSensitive: false)),
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\bRuntime\.getRuntime\(\)\.exec\s*\(')),
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\bProcess\.start\s*\(', caseSensitive: false)),
    CodePattern(CodeCategory.injection, 'code_exec.injection',
        RegExp(r'\bFunction\s*\(', caseSensitive: true)),

    // Filesystem
    CodePattern(
        CodeCategory.filesystem,
        'code_exec.filesystem',
        RegExp(r'\bFile\.delete\b|\bDirectory\.delete\b',
            caseSensitive: false)),
    CodePattern(CodeCategory.filesystem, 'code_exec.filesystem',
        RegExp(r'\bunlink\s*\(', caseSensitive: false)),
    CodePattern(CodeCategory.filesystem, 'code_exec.filesystem',
        RegExp(r'\bshutil\.rmtree\s*\(', caseSensitive: false)),
  ];

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];

    for (final p in patterns) {
      if (!categories.contains(p.category)) continue;
      for (final m in p.regex.allMatches(text)) {
        findings.add(Finding(
          type: p.type,
          start: m.start,
          end: m.end,
          match: m[0],
        ));
      }
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);

    final kinds = findings.map((f) => f.match).toSet().join(', ');
    if (action == GuardAction.warn) {
      return ScanResult.warn(
        name,
        text,
        score: 1.0,
        findings: findings,
        reason: 'dangerous code detected: $kinds',
      );
    }
    return ScanResult.block(
      name,
      text,
      findings: findings,
      reason: 'blocked: code_exec',
    );
  }
}
