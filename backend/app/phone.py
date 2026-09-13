from __future__ import annotations

import re

_PERSIAN = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def normalize_iran_mobile(value: str) -> str:
    mobile = re.sub(r"[\s\-()]+", "", (value or "").strip().translate(_PERSIAN))
    if mobile.startswith("0098"):
        mobile = "+98" + mobile[4:]
    elif mobile.startswith("98") and not mobile.startswith("+"):
        mobile = "+" + mobile
    elif mobile.startswith("09"):
        mobile = "+98" + mobile[1:]
    elif re.fullmatch(r"9\d{9}", mobile):
        mobile = "+98" + mobile
    return mobile


def is_valid_iran_mobile(value: str) -> bool:
    return re.fullmatch(r"\+989\d{9}", normalize_iran_mobile(value)) is not None
