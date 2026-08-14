/// PII detection patterns for [PiiScanner].
///
/// Every [RegExp] here is deliberately flat: bounded quantifiers, no nested
/// or overlapping repetition groups, so scanning stays linear (ReDoS-safe).
library;

/// Region a pattern applies to. `all`-ish coverage is expressed by listing
/// every relevant locale in [PiiPattern.locales].
enum PiiLocale { us, eu, india }

/// One named PII pattern with the locales it belongs to.
class PiiPattern {
  /// Bare type, e.g. `email`, `credit_card`. Findings become `pii.<type>`.
  final String type;

  /// Locales this pattern is relevant for; used to filter by region.
  final Set<PiiLocale> locales;

  /// The (ReDoS-safe) matcher.
  final RegExp regex;

  /// When `true`, matches must additionally pass a Luhn checksum.
  final bool luhn;

  const PiiPattern({
    required this.type,
    required this.locales,
    required this.regex,
    this.luhn = false,
  });
}

const Set<PiiLocale> _all = {PiiLocale.us, PiiLocale.eu, PiiLocale.india};

/// The catalogue of PII patterns scanned by [PiiScanner].
///
/// Not `const` because [RegExp] has no const constructor; the list itself is
/// immutable in practice — treat it as read-only.
final List<PiiPattern> kPiiPatterns = [
  PiiPattern(
    type: 'email',
    locales: _all,
    regex: RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
  ),
  // US phone: optional +1, optional area-code parens, common separators.
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.us},
    regex: RegExp(
      r'\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b',
    ),
  ),
  // EU phone: leading + country code then 2-4 digit groups.
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.eu},
    regex: RegExp(
      r'\+\d{1,3}[-.\s]?\d{2,4}[-.\s]?\d{2,4}[-.\s]?\d{2,4}',
    ),
  ),
  // India mobile: optional +91, then a 10-digit number starting 6-9.
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.india},
    regex: RegExp(r'\b(?:\+?91[-.\s]?)?[6-9]\d{9}\b'),
  ),
  PiiPattern(
    type: 'ssn',
    locales: const {PiiLocale.us},
    regex: RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
  ),
  // Credit card: bare 13-19 digit run, or 4-digit groups (2-4 of them).
  PiiPattern(
    type: 'credit_card',
    locales: _all,
    regex: RegExp(r'\b(?:\d{13,19}|\d{4}(?:[ -]?\d{4}){2,4})\b'),
    luhn: true,
  ),
  PiiPattern(
    type: 'iban',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b'),
  ),
  PiiPattern(
    type: 'ip',
    locales: _all,
    regex: RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
  ),
  PiiPattern(
    type: 'aadhaar',
    locales: const {PiiLocale.india},
    regex: RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b'),
  ),
  PiiPattern(
    type: 'pan',
    locales: const {PiiLocale.india},
    regex: RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b'),
  ),
  // Generic passport: one letter followed by 7 digits.
  PiiPattern(
    type: 'passport',
    locales: _all,
    regex: RegExp(r'\b[A-Z]\d{7}\b'),
  ),
];
