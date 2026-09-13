import 'package:flutter_test/flutter_test.dart';
import 'package:delta_peak_app/utils/persian_normalizer.dart';

void main() {
  test('Arabic characters normalize to Persian', () {
    expect(
      PersianNormalizer.normalizeText('  كوه  دماوند ايران '),
      'کوه دماوند ایران',
    );
  });

  test('diacritics and tatweel are removed while ZWNJ is preserved', () {
    expect(PersianNormalizer.normalizeText('اَلـبُرز  مركزی'), 'البرز مرکزی');
    expect(PersianNormalizer.normalizeText('کوه\u200Cنوردی'), 'کوه\u200Cنوردی');
  });

  test('Persian and Arabic digits normalize before numeric parsing', () {
    expect(PersianNormalizer.normalizeNumberInput('۳۹۶۲'), '3962');
    expect(PersianNormalizer.normalizeNumberInput('٣٥٫٧٢'), '35.72');
  });

  test('live input normalization preserves a trailing space', () {
    expect(PersianNormalizer.normalizeTextForInput('كوه '), 'کوه ');
  });

}
