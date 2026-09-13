class PersianNormalizer {
  PersianNormalizer._();

  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _latinDigits = '0123456789';

  static final RegExp _arabicDiacritics =
      RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]');
  static final RegExp _spaces = RegExp(r'[ \t\r\n\f\v]+');

  /// Live input normalization. ZWNJ (نیم‌فاصله / U+200C) is intentionally
  /// preserved, and trailing spaces are kept so multi-word typing stays natural.
  static String normalizeTextForInput(String? input) {
    if (input == null || input.isEmpty) return '';

    var value = input
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u202F', ' ')
        .replaceAll('ي', 'ی')
        .replaceAll('ى', 'ی')
        .replaceAll('ے', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ۀ', 'ه')
        .replaceAll('ة', 'ه')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ـ', '');

    value = value.replaceAll(_arabicDiacritics, '');
    return value.replaceAll(_spaces, ' ');
  }

  /// Canonical form used before saving Persian text in DPA.
  static String normalizeText(String? input) =>
      normalizeTextForInput(input).trim();

  static String? normalizeNullableText(String? input) {
    final value = normalizeText(input);
    return value.isEmpty ? null : value;
  }

  static String normalizeDigits(String? input) {
    if (input == null || input.isEmpty) return '';
    var value = input;
    for (var i = 0; i < 10; i++) {
      value = value
          .replaceAll(_persianDigits[i], _latinDigits[i])
          .replaceAll(_arabicDigits[i], _latinDigits[i]);
    }
    return value;
  }

  /// Normalizes localized digits and separators before int/double parsing.
  static String normalizeNumberInput(String? input) {
    var value = normalizeDigits(input).trim();
    value = value
        .replaceAll('٬', '')
        .replaceAll('٫', '.')
        .replaceAll('،', ',')
        .replaceAll('−', '-')
        .replaceAll('–', '-');

    // DPA numeric fields accept a decimal dot. A comma is treated as decimal
    // separator when entered by the user.
    value = value.replaceAll(',', '.');
    return value;
  }

  static String normalizeSearch(String? input) =>
      normalizeText(input).toLowerCase();

  static bool isMissingPlaceholder(Object? value) {
    if (value == null) return true;
    final text = normalizeSearch(value.toString());
    if (text.isEmpty) return true;
    return const {
      'n/a',
      'na',
      'unknown',
      'نامشخص',
      '-',
      '--',
      '?',
    }.contains(text);
  }
}
