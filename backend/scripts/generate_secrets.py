from __future__ import annotations

import secrets


if __name__ == "__main__":
    print(f"DPA_JWT_SECRET={secrets.token_urlsafe(48)}")
    print(f"DPA_OTP_PEPPER={secrets.token_urlsafe(48)}")
    print(f"DPA_POSTGRES_PASSWORD={secrets.token_urlsafe(32)}")
