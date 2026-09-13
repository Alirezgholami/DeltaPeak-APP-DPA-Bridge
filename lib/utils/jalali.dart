class JalaliDate {
  const JalaliDate._();

  static String now() => fromDateTime(DateTime.now());

  static String fromUtcIso(String? value) {
    if (value == null || value.trim().isEmpty) return 'ثبت نشده';
    final dt = DateTime.tryParse(value);
    if (dt == null) return value;
    return fromDateTime(dt.toLocal());
  }

  static String fromDateTime(DateTime dt) {
    final g = _toJalali(dt.year, dt.month, dt.day);
    return '${g.$1.toString().padLeft(4, '0')}/'
        '${g.$2.toString().padLeft(2, '0')}/'
        '${g.$3.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  static (int, int, int) _toJalali(int gy, int gm, int gd) {
    const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    final gy2 = gm > 2 ? gy + 1 : gy;
    var days = 355666 +
        365 * gy +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) +
        gd +
        gdm[gm - 1];
    var jy = -1595 + 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
    final jd = days < 186 ? 1 + days % 31 : 1 + (days - 186) % 30;
    return (jy, jm, jd);
  }
}
