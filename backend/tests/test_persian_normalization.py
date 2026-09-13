from app.persian_normalizer import normalize_digits, normalize_persian_text


def test_persian_text_normalization():
    assert normalize_persian_text('  كوه   دماوند ايران  ') == 'کوه دماوند ایران'
    assert normalize_persian_text('اَلـبُرز  مركزی') == 'البرز مرکزی'


def test_digit_normalization():
    assert normalize_digits('۳۹۶۲ / ٣٥') == '3962 / 35'
