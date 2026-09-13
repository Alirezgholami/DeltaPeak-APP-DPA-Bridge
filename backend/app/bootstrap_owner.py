from __future__ import annotations

import getpass
import os

from sqlalchemy import select

from .db import SessionLocal, init_db
from .models import User
from .phone import is_valid_iran_mobile, normalize_iran_mobile
from .security import hash_password, utcnow


def main() -> None:
    init_db()
    mobile = normalize_iran_mobile(os.getenv("DPA_OWNER_MOBILE") or input("Owner mobile: "))
    if not is_valid_iran_mobile(mobile):
        raise SystemExit("Invalid Iranian mobile number.")
    name = (os.getenv("DPA_OWNER_NAME") or input("Owner display name: ")).strip() or "Owner"
    password = os.getenv("DPA_OWNER_PASSWORD") or getpass.getpass("Owner password (min 8 chars): ")
    if len(password) < 8:
        raise SystemExit("Password must be at least 8 characters.")
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.mobile == mobile))
        if user is None:
            user = User(
                display_name=name,
                mobile=mobile,
                username=mobile,
                password_hash=hash_password(password),
                role="owner",
                status="active",
                last_activity_at=utcnow(),
            )
            db.add(user)
        else:
            user.display_name = name
            user.password_hash = hash_password(password)
            user.role = "owner"
            user.status = "active"
            user.last_activity_at = utcnow()
        db.commit()
        print(f"Owner ready: {mobile}")


if __name__ == "__main__":
    main()
