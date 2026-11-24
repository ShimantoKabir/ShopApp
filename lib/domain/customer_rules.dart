import '../core/bangla.dart';

/// Rules for customer details. Pure functions, shared by the screens (to give
/// instant feedback) and the repository (the final authority).

/// Keeps only digits, accepting Bangla or English digits.
String digitsOnly(String raw) {
  final ascii = StringBuffer();
  for (final r in raw.runes) {
    final c = String.fromCharCode(r);
    final bn = banglaDigitValue(c);
    ascii.write(bn ?? c);
  }
  return ascii.toString().replaceAll(RegExp(r'[^0-9]'), '');
}

/// A Bangladeshi mobile number as the usual 11 digits ("01712345678"), from
/// input like "০১৭১২-৩৪৫৬৭৮", "+8801712345678" or "8801712345678".
/// Returns the digits as typed (without a country code) if it can't be normalised.
String normalizeMobile(String raw) {
  var d = digitsOnly(raw);
  if (d.startsWith('880') && d.length == 13) d = '0${d.substring(3)}';
  return d;
}

/// 11 digits: 01 + operator digit 3-9 + 8 digits.
bool isValidMobile(String raw) => RegExp(r'^01[3-9][0-9]{8}$').hasMatch(normalizeMobile(raw));

/// The number in international form for WhatsApp ("8801712345678"), or null
/// if it isn't a valid Bangladeshi mobile number.
String? whatsAppNumber(String raw) {
  if (!isValidMobile(raw)) return null;
  return '880${normalizeMobile(raw).substring(1)}';
}

/// Bangladeshi NIDs have 10 digits (smart card), 17 (old, with birth year) or
/// 13 (the old number without the year).
String normalizeNid(String raw) => digitsOnly(raw);

bool isValidNid(String raw) {
  final n = normalizeNid(raw).length;
  return n == 10 || n == 13 || n == 17;
}
