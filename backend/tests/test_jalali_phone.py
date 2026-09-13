from datetime import datetime, timezone

from app.jalali import jalali_datetime
from app.phone import is_valid_iran_mobile, normalize_iran_mobile


def test_phone_normalization():
    assert normalize_iran_mobile("۰۹۱۲ ۱۲۳ ۴۵۶۷") == "+989121234567"
    assert normalize_iran_mobile("00989121234567") == "+989121234567"
    assert is_valid_iran_mobile("+989121234567")


def test_jalali_known_nowruz():
    assert jalali_datetime(datetime(2026, 3, 21, 0, 0, tzinfo=timezone.utc)).startswith("1405/01/01")
