class PhoneUtils {
  static String normalizeIranMobile(String input) {
    var value = input
        .trim()
        .replaceAll(RegExp(r'[\s\-()]+'), '')
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9')
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');

    if (value.startsWith('0098')) value = '+98${value.substring(4)}';
    if (value.startsWith('98') && !value.startsWith('+')) value = '+$value';
    if (value.startsWith('09')) value = '+98${value.substring(1)}';
    if (RegExp(r'^9\d{9}$').hasMatch(value)) value = '+98$value';
    return value;
  }

  static bool isValidIranMobile(String input) =>
      RegExp(r'^\+989\d{9}$').hasMatch(normalizeIranMobile(input));
}
