from __future__ import annotations

import re

_ARABIC_DIACRITICS = re.compile(r'[\u064B-\u065F\u0670\u06D6-\u06ED]')
_SPACES = re.compile(r'[ \t\r\n\f\v]+')
_DIGIT_MAP = str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩', '01234567890123456789')


def normalize_persian_text(value: str | None) -> str:
    if not value:
        return ''
    text = value.replace('\u00a0', ' ').replace('\u202f', ' ')
    replacements = {
        'ي': 'ی', 'ى': 'ی', 'ے': 'ی', 'ك': 'ک', 'ۀ': 'ه', 'ة': 'ه',
        'أ': 'ا', 'إ': 'ا', 'ٱ': 'ا', 'ـ': '',
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    text = _ARABIC_DIACRITICS.sub('', text)
    return _SPACES.sub(' ', text).strip()


def normalize_digits(value: str | None) -> str:
    return (value or '').translate(_DIGIT_MAP)
