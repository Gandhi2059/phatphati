// Nepal Mobile Number Normalization, Validation, and Utilities
// Supports E.164 format (+97798XXXXXXXX / +97797XXXXXXXX) according to NTA standards.

class NepalPhoneHelper {
  // Nepal Mobile numbers are 10 digits starting with 98, 97, or 96
  static final RegExp _nepalMobileRegex = RegExp(
    r'^(?:\+?977|00977)?\s*[-.]?\s*(9[678]\d{8})$',
  );

  /// Validates whether the given string is a valid Nepal mobile number.
  static bool isValid(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    return _nepalMobileRegex.hasMatch(cleaned);
  }

  /// Normalizes a valid Nepal mobile number to E.164 format (e.g., +9779841234567).
  /// Returns null if the number is invalid.
  static String? normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    final match = _nepalMobileRegex.firstMatch(cleaned);
    if (match != null) {
      final tenDigits = match.group(1);
      return '+977$tenDigits';
    }
    return null;
  }

  /// Extracts the 10-digit national number (e.g., 9841234567).
  static String? extractNational(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    final match = _nepalMobileRegex.firstMatch(cleaned);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  /// Formats a Nepal number for friendly UI display (e.g., +977 984-1234567).
  static String formatDisplay(String? raw) {
    final normalized = normalize(raw);
    if (normalized != null && normalized.length == 14) {
      final prefix = normalized.substring(0, 4); // +977
      final operatorCode = normalized.substring(4, 7); // 984
      final subscriber = normalized.substring(7); // 1234567
      return '$prefix $operatorCode-$subscriber';
    }
    return raw?.trim() ?? '';
  }

  /// Masks a phone number for privacy display (e.g., +977 984***4567).
  static String maskPhone(String? raw) {
    final normalized = normalize(raw);
    if (normalized != null && normalized.length == 14) {
      final prefix = normalized.substring(0, 4); // +977
      final operatorCode = normalized.substring(4, 7); // 984
      final tail = normalized.substring(10); // 4567
      return '$prefix $operatorCode***$tail';
    }
    return raw ?? '';
  }

  /// Checks if two phone inputs represent the exact same normalized phone number.
  static bool areSame(String? phoneA, String? phoneB) {
    final normA = normalize(phoneA);
    final normB = normalize(phoneB);
    if (normA == null || normB == null) return false;
    return normA == normB;
  }
}
