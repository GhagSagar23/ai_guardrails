import '../scanner.dart';

/// Detects demographic bias indicators in generated text.
///
/// Heuristic scanner checking for gendered generalisations, age stereotypes,
/// and demographic assumptions. Optional [LlmCallback] for deeper analysis.
class BiasScanner extends AsyncScanner with LlmDependent {
  final bool useLlm;
  final GuardAction action;

  BiasScanner({
    this.useLlm = false,
    this.action = GuardAction.warn,
  });

  @override
  String get name => 'bias';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  static final _patterns = <_BiasPattern>[
    _BiasPattern(
      'bias.gender_generalisation',
      RegExp(
        r'\b(all\s+(?:women|men|girls|boys)\s+(?:are|should|must|need|always|never))\b',
        caseSensitive: false,
      ),
    ),
    _BiasPattern(
      'bias.age_stereotype',
      RegExp(
        r'\b((?:old|elderly|young)\s+people\s+(?:are|always|never|cant|cannot|can'
        "'"
        r't))\b',
        caseSensitive: false,
      ),
    ),
    _BiasPattern(
      'bias.racial_generalisation',
      RegExp(
        r'\b((?:all|every|most)\s+(?:black|white|asian|hispanic|latino|latina)\s+people\s+(?:are|should|always|never))\b',
        caseSensitive: false,
      ),
    ),
    _BiasPattern(
      'bias.ability_assumption',
      RegExp(
        r'\b((?:disabled|handicapped)\s+people\s+(?:cant|cannot|can'
        "'"
        r't|are\s+unable|should\s+not))\b',
        caseSensitive: false,
      ),
    ),
    _BiasPattern(
      'bias.gender_role',
      RegExp(
        r'\b((?:women|men)\s+(?:belong|should\s+stay|are\s+meant)\s+(?:in|at)\s+(?:the\s+)?(?:home|kitchen|office|workplace))\b',
        caseSensitive: false,
      ),
    ),
  ];

  @override
  Future<ScanResult> scanAsync(
    String text, {
    ScanStage stage = ScanStage.input,
  }) async {
    final findings = <Finding>[];

    for (final bp in _patterns) {
      for (final m in bp.pattern.allMatches(text)) {
        findings.add(Finding(
          type: bp.type,
          start: m.start,
          end: m.end,
          match: m.group(0),
        ));
      }
    }

    if (useLlm && findings.isEmpty) {
      final llmFindings = await _llmScan(text);
      findings.addAll(llmFindings);
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final reason = '${findings.length} bias indicator(s) detected';
    if (action == GuardAction.block) {
      return ScanResult.block(name, text, findings: findings, reason: reason);
    }
    return ScanResult.warn(name, text, findings: findings, reason: reason);
  }

  Future<List<Finding>> _llmScan(String text) async {
    final prompt = 'Analyze the following text for demographic bias, '
        'stereotypes, or unfair generalisations about any group '
        '(gender, race, age, disability, religion, etc.).\n\n'
        'Text: $text\n\n'
        'Reply "NONE" if no bias found, or list each bias on a separate '
        'line starting with "BIAS: ".';
    final response = await llmCallback(prompt);
    if (response.trim().toUpperCase() == 'NONE') return [];
    final lines = response.split('\n').where((l) => l.startsWith('BIAS: '));
    return [
      for (final line in lines)
        Finding(type: 'bias.llm', match: line.substring(6).trim()),
    ];
  }
}

class _BiasPattern {
  final String type;
  final RegExp pattern;
  const _BiasPattern(this.type, this.pattern);
}
