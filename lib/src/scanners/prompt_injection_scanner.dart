import '../scanner.dart';

/// One weighted heuristic group used by [PromptInjectionScanner].
///
/// A group fires (contributing its [weight] once, plus one [Finding] per raw
/// match) when *any* of its [patterns] match the scanned text.
class InjectionSignal {
  /// Short signal name, used in finding types as `injection.<name>`.
  final String name;

  /// Contribution to the total score when this group fires. `0.0`..`1.0`.
  final double weight;

  /// Alternative regexes; matching any one fires the group.
  final List<RegExp> patterns;

  const InjectionSignal(this.name, this.weight, this.patterns);
}

RegExp _ci(String source) => RegExp(source, caseSensitive: false);

/// The tunable signal table. Edit weights/patterns here to retune detection.
///
/// Scoring is additive over the groups that fire, clamped to `0.0`..`1.0`.
/// A single strong group (override / exfiltration / jailbreak) already meets
/// the default `0.5` threshold; weaker groups must combine to block.
final List<InjectionSignal> kInjectionSignals = [
  InjectionSignal('instruction_override', 0.6, [
    _ci(
      r'\b(ignore|disregard|forget|override)\b[^\n]{0,40}?\b(instructions?|prompts?|context|above|previous|prior|earlier)\b',
    ),
  ]),
  InjectionSignal('system_prompt_exfiltration', 0.6, [
    _ci(
      r'\b(reveal|show|print|expose|display|tell me)\b[^\n]{0,30}?\b(system\s+)?(prompt|instructions?)\b',
    ),
    _ci(r'\b(repeat|print|echo|reveal|show)\b[^\n]{0,30}?\b(the (words|text|lines?) )?above\b'),
    _ci(r'\bwhat (is|are) your\b[^\n]{0,25}?\b(system\s+)?(prompt|instructions?)\b'),
  ]),
  InjectionSignal('roleplay_jailbreak', 0.5, [
    _ci(r'\byou are (now )?dan\b'),
    _ci(r'\bdo anything now\b'),
    _ci(r'\bact as\b'),
    _ci(r'\bdeveloper mode\b'),
    _ci(r'\bpretend\b'),
    _ci(r'\bjailbreak\b'),
  ]),
  InjectionSignal('delimiter_attack', 0.4, [
    _ci(r'#{2,}\s*(system|assistant|user)\b'),
    _ci(r'<\|im_start\|>'),
    _ci(r'<\|im_end\|>'),
    _ci(r'\[/?INST\]'),
    _ci(r'<<SYS>>'),
  ]),
  InjectionSignal('behavior_change', 0.35, [
    _ci(r'\bfrom now on\b'),
    _ci(r'\bnew instructions?\b'),
    _ci(r'\bfrom this (point|moment) (on|forward|onward)\b'),
    _ci(r'\bstarting now\b'),
  ]),
];

/// Heuristic prompt-injection detector.
///
/// Runs the [kInjectionSignals] table over the text, sums the weights of the
/// groups that fired, clamps to `0.0`..`1.0`, and blocks when the score meets
/// [threshold]. Input-stage only.
class PromptInjectionScanner implements Scanner {
  /// Score at/above which [GuardAction.block] rejects the text.
  final double threshold;

  /// What to do when the score meets [threshold].
  final GuardAction action;

  const PromptInjectionScanner({
    this.threshold = 0.5,
    this.action = GuardAction.block,
  });

  @override
  String get name => 'prompt_injection';

  @override
  Set<ScanStage> get stages => const {ScanStage.input};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final findings = <Finding>[];
    final matched = <InjectionSignal>[];
    var sum = 0.0;

    for (final sig in kInjectionSignals) {
      var hit = false;
      for (final p in sig.patterns) {
        for (final m in p.allMatches(text)) {
          hit = true;
          findings.add(Finding(
            type: 'injection.${sig.name}',
            start: m.start,
            end: m.end,
            match: m[0],
            confidence: sig.weight.clamp(0.0, 1.0),
          ));
        }
      }
      if (hit) {
        matched.add(sig);
        sum += sig.weight;
      }
    }

    final score = sum > 1.0 ? 1.0 : sum;

    if (findings.isEmpty) return ScanResult.pass(name, text);

    switch (action) {
      case GuardAction.block:
        if (score >= threshold) {
          return ScanResult(
            scanner: name,
            passed: false,
            text: text,
            score: score,
            findings: findings,
            reason: 'prompt injection score ${score.toStringAsFixed(2)} '
                '>= threshold ${threshold.toStringAsFixed(2)}; '
                'signals: ${matched.map((s) => s.name).join(', ')}',
          );
        }
        return ScanResult(
          scanner: name,
          passed: true,
          text: text,
          score: score,
          findings: findings,
          reason: 'below threshold (${score.toStringAsFixed(2)} < '
              '${threshold.toStringAsFixed(2)})',
        );

      case GuardAction.warn:
        return ScanResult(
          scanner: name,
          passed: true,
          text: text,
          score: score,
          findings: findings,
        );

      case GuardAction.redact:
        var out = text;
        for (final sig in matched) {
          for (final p in sig.patterns) {
            out = out.replaceAll(p, '[INJECTION]');
          }
        }
        return ScanResult(
          scanner: name,
          passed: true,
          text: out,
          score: score,
          findings: findings,
          reason: 'redacted ${findings.length} injection span(s)',
        );

      case GuardAction.hash:
        var out = text;
        for (final sig in matched) {
          for (final p in sig.patterns) {
            out = out.replaceAllMapped(
              p,
              (m) => '[INJECTION:${_fnv1a(m[0]!)}]',
            );
          }
        }
        return ScanResult(
          scanner: name,
          passed: true,
          text: out,
          score: score,
          findings: findings,
          reason: 'hashed ${findings.length} injection span(s)',
        );
    }
  }
}

/// Tiny local FNV-1a (32-bit) → 6 hex chars. No crypto dependency.
String _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0').substring(2);
}
