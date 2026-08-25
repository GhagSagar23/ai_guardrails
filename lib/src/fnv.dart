/// FNV-1a (32-bit) → 6 hex chars. Stable, non-cryptographic;
/// used to make hashed placeholders deterministic without a dependency.
String fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0').substring(2);
}
