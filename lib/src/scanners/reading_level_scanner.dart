import 'dart:math';

import '../scanner.dart';

/// Enforces reading grade level bounds on generated text.
///
/// Computes Flesch-Kincaid grade level and Coleman-Liau index, then checks
/// against [minGrade] and [maxGrade]. Pure math — zero dependencies.
class ReadingLevelScanner implements Scanner {
  final double? minGrade;
  final double? maxGrade;
  final GuardAction action;

  ReadingLevelScanner({
    this.minGrade,
    this.maxGrade,
    this.action = GuardAction.warn,
  });

  @override
  String get name => 'reading_level';

  @override
  Set<ScanStage> get stages => const {ScanStage.output};

  @override
  ScanResult scan(String text, {ScanStage stage = ScanStage.input}) {
    final sentences = _countSentences(text);
    final words = _countWords(text);
    final syllables = _countSyllables(text);
    final chars = _countLetters(text);

    if (words < 3 || sentences == 0) return ScanResult.pass(name, text);

    final fk = _fleschKincaid(words, sentences, syllables);
    final cl = _colemanLiau(chars, words, sentences);
    final grade = (fk + cl) / 2;

    final findings = <Finding>[];
    if (minGrade != null && grade < minGrade!) {
      findings.add(Finding(
        type: 'reading_level.too_simple',
        match: 'grade ${grade.toStringAsFixed(1)} < $minGrade',
      ));
    }
    if (maxGrade != null && grade > maxGrade!) {
      findings.add(Finding(
        type: 'reading_level.too_complex',
        match: 'grade ${grade.toStringAsFixed(1)} > $maxGrade',
      ));
    }

    if (findings.isEmpty) return ScanResult.pass(name, text);
    final reason = 'reading level ${grade.toStringAsFixed(1)} outside '
        '[${minGrade ?? '-inf'}..${maxGrade ?? '+inf'}]';
    if (action == GuardAction.block) {
      return ScanResult.block(name, text, findings: findings, reason: reason);
    }
    return ScanResult.warn(name, text, findings: findings, reason: reason);
  }

  double _fleschKincaid(int words, int sentences, int syllables) =>
      0.39 * (words / sentences) + 11.8 * (syllables / words) - 15.59;

  double _colemanLiau(int chars, int words, int sentences) {
    final l = chars / words * 100;
    final s = sentences / words * 100;
    return 0.0588 * l - 0.296 * s - 15.8;
  }

  static final _sentenceEnd = RegExp(r'[.!?]+');
  static final _wordPattern = RegExp(r"[a-zA-Z']+");

  int _countSentences(String text) =>
      max(1, _sentenceEnd.allMatches(text).length);

  int _countWords(String text) => _wordPattern.allMatches(text).length;

  int _countLetters(String text) => text.codeUnits
      .where((c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122))
      .length;

  int _countSyllables(String text) {
    var total = 0;
    for (final m in _wordPattern.allMatches(text)) {
      total += _syllablesInWord(m.group(0)!.toLowerCase());
    }
    return max(1, total);
  }

  // ponytail: simple vowel-group heuristic, good enough for grade-level
  int _syllablesInWord(String word) {
    if (word.length <= 2) return 1;
    var count = 0;
    var prevVowel = false;
    for (var i = 0; i < word.length; i++) {
      final isVowel = 'aeiouy'.contains(word[i]);
      if (isVowel && !prevVowel) count++;
      prevVowel = isVowel;
    }
    if (word.endsWith('e') && count > 1) count--;
    return max(1, count);
  }
}
