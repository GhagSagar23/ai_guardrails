import '../scanner.dart';

/// Categories scored by [ToxicityScanner].
enum ToxCategory {
  /// General insults and profanity.
  toxicity,

  /// Targeted abuse, intimidation and stalking.
  harassment,

  /// Hate speech against groups.
  hate,

  /// Suicide and self-injury.
  selfHarm,

  /// Sexually explicit content.
  sexual,

  /// Threats and graphic violence.
  violence,
}

/// Heuristic toxicity scanner scoring text across [ToxCategory] values.
///
/// Each category has weighted regex patterns. Category score is
/// `matched / total`, boosted by the highest severity among matched patterns,
/// clamped to 1.0. The overall score is the weighted average of the categories
/// that matched; the scan blocks (or warns) when it reaches [threshold].
// ponytail: heuristic keyword scoring; upgrade to ML classifier when tflite_flutter matures
class ToxicityScanner implements Scanner {
  /// Overall score (0.0–1.0) at or above which the action is taken.
  final double threshold;

  /// The action taken when the score reaches [threshold].
  final GuardAction action;

  /// Categories to check. Defaults to all.
  final Set<ToxCategory> categories;

  /// Creates a [ToxicityScanner].
  ToxicityScanner({
    this.threshold = 0.7,
    this.action = GuardAction.block,
    Set<ToxCategory>? categories,
  }) : categories = categories ?? ToxCategory.values.toSet();

  @override
  String get name => 'toxicity';

  @override
  Set<ScanStage> get stages => const {ScanStage.input, ScanStage.output};

  // Relative weight of each category in the overall average.
  static const _categoryWeight = <ToxCategory, double>{
    ToxCategory.toxicity: 0.6,
    ToxCategory.harassment: 0.8,
    ToxCategory.hate: 1.0,
    ToxCategory.selfHarm: 1.0,
    ToxCategory.sexual: 0.7,
    ToxCategory.violence: 1.0,
  };

  static final _patterns = <ToxCategory, List<_ToxPattern>>{
    ToxCategory.toxicity: [
      _ToxPattern(r'\bidi[o0]ts?\b', 0.4),
      _ToxPattern(r'\bst[u]pid\b', 0.3),
      _ToxPattern(r'\bm[o0]r[o0]ns?\b', 0.4),
      _ToxPattern(r'\bscum(?:bag)?\b', 0.5),
      _ToxPattern(r'\bf[u*]ck\s+(?:you|off)\b', 0.8),
      _ToxPattern(r'\bpiece\s+of\s+(?:sh[i1]t|trash|garbage)\b', 0.8),
      _ToxPattern(r'\bd[u]mb(?:ass)?\b', 0.3),
      _ToxPattern(r'\bi\s+hate\s+you\b', 0.5),
      _ToxPattern(r'\bsh[i1]t(?:head|bag)\b', 0.6),
    ],
    ToxCategory.harassment: [
      _ToxPattern(
          r"\byou(?:'re|\s+are)\s+(?:worthless|pathetic|disgusting|a\s+loser)\b",
          0.7),
      _ToxPattern(r'\bnobody\s+(?:likes|loves|cares\s+about)\s+you\b', 0.6),
      _ToxPattern(r"\bi(?:'ll|\s+will)\s+find\s+you\b", 0.9),
      _ToxPattern(r'\bshut\s+(?:up|your\s+(?:mouth|face))\b', 0.4),
      _ToxPattern(r'\bk[i1]ll\s+yourself\b', 1.0),
      _ToxPattern(r'\bgo\s+(?:die|rot)\b', 0.9),
      _ToxPattern(r'\byou\s+deserve\s+to\s+(?:suffer|die|be\s+hurt)\b', 0.9),
      _ToxPattern(r'\bd[o0]xx?(?:ing|ed)?\b', 0.8),
      _ToxPattern(r'\bi(?:\s+am|\x27m)\s+(?:watching|following)\s+you\b', 0.7),
    ],
    ToxCategory.hate: [
      _ToxPattern(
          r'\b(?:all|those)\s+\w+\s+should\s+(?:die|be\s+(?:exterminated|eradicated|killed))\b',
          1.0),
      _ToxPattern(r'\bsub-?human\b', 0.8),
      _ToxPattern(r'\bvermin\b', 0.6),
      _ToxPattern(r'\bgo\s+back\s+to\s+(?:your|where\s+you)\b', 0.7),
      _ToxPattern(r'\bethnic\s+cleansing\b', 0.9),
      _ToxPattern(r'\bwh[i1]te\s+p[o0]wer\b', 0.8),
      _ToxPattern(r'\bmaster\s+race\b', 0.8),
      _ToxPattern(r'\binferior\s+(?:race|people|breed)\b', 0.8),
      _ToxPattern(
          r'\bgenocide\s+(?:is|was)\s+(?:good|justified|deserved)\b', 1.0),
    ],
    ToxCategory.selfHarm: [
      _ToxPattern(r'\bk[i1]ll\s+myself\b', 1.0),
      _ToxPattern(r'\bcommit(?:ting)?\s+suic[i1]de\b', 1.0),
      _ToxPattern(r'\bwant\s+to\s+d[i1]e\b', 0.9),
      _ToxPattern(r'\bend\s+my\s+(?:own\s+)?l[i1]fe\b', 1.0),
      _ToxPattern(r'\bcut(?:ting)?\s+myself\b', 0.9),
      _ToxPattern(r'\bself[-\s]?harm(?:ing)?\b', 0.6),
      _ToxPattern(r'\bsuic[i1]d(?:e|al)\b', 0.6),
      _ToxPattern(r'\bhurt(?:ing)?\s+myself\b', 0.8),
      _ToxPattern(r'\bno\s+reason\s+to\s+l[i1]ve\b', 0.9),
    ],
    ToxCategory.sexual: [
      _ToxPattern(r'\bp[o0]rn(?:o|ography)?\b', 0.7),
      _ToxPattern(r'\bn[u]de\s+(?:pics?|photos?|images?)\b', 0.8),
      _ToxPattern(r'\bs[e3]x\s+tape\b', 0.8),
      _ToxPattern(r'\bh[o0]rny\b', 0.6),
      _ToxPattern(r'\borgasm(?:s)?\b', 0.6),
      _ToxPattern(r'\berotic\b', 0.4),
      _ToxPattern(r'\bgenitals?\b', 0.5),
      _ToxPattern(r'\bexplicit\s+s[e3]x(?:ual)?\b', 0.8),
      _ToxPattern(r'\bs[e3]xual\s+(?:act|content|favou?rs)\b', 0.5),
    ],
    ToxCategory.violence: [
      _ToxPattern(
          r'\bk[i1]ll\s+(?:you|him|her|them|everyone|everybody)\b', 1.0),
      _ToxPattern(r'\bmurder(?:ed|ing|s)?\b', 0.7),
      _ToxPattern(r'\bi(?:\s+will|\x27ll)\s+(?:hurt|stab|shoot|beat)\b', 1.0),
      _ToxPattern(r'\bb[o0]mb(?:ing)?\b', 0.5),
      _ToxPattern(r'\bmassacre\b', 0.8),
      _ToxPattern(r'\bslit\s+(?:your|his|her|their)\s+throat\b', 1.0),
      _ToxPattern(r'\btortur(?:e|ing)\b', 0.6),
      _ToxPattern(r'\bbehead(?:ed|ing)?\b', 0.8),
      _ToxPattern(r'\bblow\s+(?:it\s+|them\s+|you\s+)?up\b', 0.6),
    ],
  };

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    if (text.isEmpty) return ScanResult.pass(name, text);

    final findings = <Finding>[];
    var weighted = 0.0;
    var weights = 0.0;

    for (final cat in categories) {
      final pats = _patterns[cat]!;
      var matched = 0;
      var maxSeverity = 0.0;
      for (final p in pats) {
        final ms = p.pattern.allMatches(text).toList();
        if (ms.isEmpty) continue;
        matched++;
        if (p.severity > maxSeverity) maxSeverity = p.severity;
        for (final m in ms) {
          findings.add(Finding(
            type: 'toxicity.${cat.name}',
            start: m.start,
            end: m.end,
            match: m.group(0),
            confidence: p.severity,
          ));
        }
      }
      if (matched == 0) continue;
      final catScore = (matched / pats.length + maxSeverity).clamp(0.0, 1.0);
      final w = _categoryWeight[cat]!;
      weighted += catScore * w;
      weights += w;
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final score = (weighted / weights).clamp(0.0, 1.0);
    if (score < threshold) return ScanResult.pass(name, text);

    final reason = 'toxicity score ${score.toStringAsFixed(2)} '
        '(threshold ${threshold.toStringAsFixed(2)})';
    if (action == GuardAction.block) {
      return ScanResult.block(name, text,
          score: score, findings: findings, reason: reason);
    }
    return ScanResult.warn(name, text,
        score: score, findings: findings, reason: reason);
  }
}

class _ToxPattern {
  final RegExp pattern;
  final double severity;
  _ToxPattern(String source, this.severity)
      : pattern = RegExp(source, caseSensitive: false);
}
