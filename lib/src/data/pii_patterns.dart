/// PII detection patterns for [PiiScanner].
///
/// Every [RegExp] here is deliberately flat: bounded quantifiers, no nested
/// or overlapping repetition groups, so scanning stays linear (ReDoS-safe).
library;

/// Region a pattern applies to. `all`-ish coverage is expressed by listing
/// every relevant locale in [PiiPattern.locales].
enum PiiLocale { us, eu, india, brazil, mexico, japan, southKorea, canada, australia }

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

  /// Minimum digit count for Luhn validation. Default 12 (credit cards).
  final int luhnMinDigits;

  const PiiPattern({
    required this.type,
    required this.locales,
    required this.regex,
    this.luhn = false,
    this.luhnMinDigits = 12,
  });
}

const Set<PiiLocale> _all = {
  PiiLocale.us, PiiLocale.eu, PiiLocale.india, PiiLocale.brazil,
  PiiLocale.mexico, PiiLocale.japan, PiiLocale.southKorea,
  PiiLocale.canada, PiiLocale.australia,
};

/// The catalogue of PII patterns scanned by [PiiScanner].
///
/// Not `const` because [RegExp] has no const constructor; the list itself is
/// immutable in practice — treat it as read-only.
final List<PiiPattern> kPiiPatterns = [
  // ── Global ──────────────────────────────────────────────────────────
  PiiPattern(
    type: 'email',
    locales: _all,
    regex: RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
  ),
  PiiPattern(
    type: 'credit_card',
    locales: _all,
    regex: RegExp(r'\b(?:\d{13,19}|\d{4}(?:[ -]?\d{4}){2,4})\b'),
    luhn: true,
  ),
  PiiPattern(
    type: 'ip',
    locales: _all,
    regex: RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
  ),
  PiiPattern(
    type: 'passport',
    locales: _all,
    regex: RegExp(r'\b[A-Z]\d{7}\b'),
  ),

  // ── US ──────────────────────────────────────────────────────────────
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.us},
    regex: RegExp(
      r'\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b',
    ),
  ),
  PiiPattern(
    type: 'ssn',
    locales: const {PiiLocale.us},
    regex: RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
  ),

  // ── EU (shared) ─────────────────────────────────────────────────────
  PiiPattern(
    type: 'iban',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b'),
  ),

  // ── EU country-specific phones ──────────────────────────────────────
  // UK: +44 or 0, then 10 digits in varying groupings
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'(?<!\w)\+44\s?\d{2,5}[-.\s]?\d{3,4}[-.\s]?\d{3,4}\b'),
  ),
  // Germany: +49 or 0, then variable-length area + subscriber
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'(?<!\w)\+49\s?\d{2,5}[-.\s]?\d{4,8}\b'),
  ),
  // France: +33, then 9 digits in pairs
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'(?<!\w)\+33\s?\d\s?\d{2}\s?\d{2}\s?\d{2}\s?\d{2}\b'),
  ),
  // Italy: +39, then 2-4 digit area + 6-8 digit subscriber
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'(?<!\w)\+39\s?\d{2,4}[-.\s]?\d{6,8}\b'),
  ),
  // Spain: +34, then 9 digits
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.eu},
    regex: RegExp(r'(?<!\w)\+34\s?\d{3}\s?\d{3}\s?\d{3}\b'),
  ),

  // ── India ───────────────────────────────────────────────────────────
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.india},
    regex: RegExp(r'(?<!\w)(?:\+?91[-.\s]?)?[6-9]\d{4}[-.\s]?\d{5}\b'),
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

  // ── Brazil ──────────────────────────────────────────────────────────
  // CPF: 000.000.000-00
  PiiPattern(
    type: 'cpf',
    locales: const {PiiLocale.brazil},
    regex: RegExp(r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b'),
  ),
  // CNPJ: 00.000.000/0000-00
  PiiPattern(
    type: 'cnpj',
    locales: const {PiiLocale.brazil},
    regex: RegExp(r'\b\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}\b'),
  ),
  // Brazil phone: +55 DDD + 8-9 digits
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.brazil},
    regex: RegExp(r'\b(?:\+?55[-.\s]?)?\(?\d{2}\)?[-.\s]?\d{4,5}[-.\s]?\d{4}\b'),
  ),

  // ── Mexico ──────────────────────────────────────────────────────────
  // CURP: 18 alphanumeric characters with specific structure
  PiiPattern(
    type: 'curp',
    locales: const {PiiLocale.mexico},
    regex: RegExp(r'\b[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d\b'),
  ),
  // RFC: 12-13 alphanumeric characters
  PiiPattern(
    type: 'rfc',
    locales: const {PiiLocale.mexico},
    regex: RegExp(r'\b[A-Z&Ñ]{3,4}\d{6}[A-Z0-9]{3}\b'),
  ),
  // Mexico phone: +52 then 10 digits
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.mexico},
    regex: RegExp(r'\b(?:\+?52[-.\s]?)?\d{2,3}[-.\s]?\d{3,4}[-.\s]?\d{4}\b'),
  ),

  // ── Japan ───────────────────────────────────────────────────────────
  // My Number: 12 digits, often with spaces
  PiiPattern(
    type: 'my_number',
    locales: const {PiiLocale.japan},
    regex: RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b'),
  ),
  // Japan phone: +81 or 0, then 9-10 digits
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.japan},
    regex: RegExp(r'(?<!\w)(?:\+81|0)\d[-.\s]?\d{4}[-.\s]?\d{4}\b'),
  ),

  // ── South Korea ─────────────────────────────────────────────────────
  // RRN: 6 digits (birthday) - 7 digits
  PiiPattern(
    type: 'rrn',
    locales: const {PiiLocale.southKorea},
    regex: RegExp(r'\b\d{6}-[1-4]\d{6}\b'),
  ),
  // Korea phone: +82 or 0, then 10-11 digits
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.southKorea},
    regex: RegExp(r'(?<!\w)(?:\+82|0)\d{2}[-.\s]?\d{3,4}[-.\s]?\d{4}\b'),
  ),

  // ── Canada ──────────────────────────────────────────────────────────
  // SIN: 000-000-000 (Luhn-checked)
  PiiPattern(
    type: 'sin',
    locales: const {PiiLocale.canada},
    regex: RegExp(r'\b\d{3}[-.\s]\d{3}[-.\s]\d{3}\b'),
    luhn: true,
    luhnMinDigits: 9,
  ),
  // Canada phone: same format as US
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.canada},
    regex: RegExp(
      r'\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b',
    ),
  ),

  // ── Australia ───────────────────────────────────────────────────────
  // TFN: 8-9 digits, often with spaces (000 000 000)
  PiiPattern(
    type: 'tfn',
    locales: const {PiiLocale.australia},
    regex: RegExp(r'\b\d{3}\s?\d{3}\s?\d{2,3}\b'),
  ),
  // Medicare: 10-11 digits (0000 00000 0)
  PiiPattern(
    type: 'medicare',
    locales: const {PiiLocale.australia},
    regex: RegExp(r'\b\d{4}\s?\d{5}\s?\d{1,2}\b'),
  ),
  // Australia phone: +61 or 0, then 9 digits
  PiiPattern(
    type: 'phone',
    locales: const {PiiLocale.australia},
    regex: RegExp(r'(?<!\w)(?:\+61|0)\s?\d\s?\d{4}\s?\d{4}\b'),
  ),
];
