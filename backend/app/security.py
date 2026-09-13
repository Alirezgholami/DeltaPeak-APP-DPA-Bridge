from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from .config import settings

_ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)
_DUMMY_PASSWORD_HASH = _ph.hash("DPA dummy password for timing equalization only")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def verify_password_or_dummy(password_hash: str | None, password: str) -> bool:
    """Always perform one Argon2 verification, even for unknown users."""
    target = password_hash or _DUMMY_PASSWORD_HASH
    valid = verify_password(target, password)
    return valid if password_hash is not None else False


def password_needs_rehash(password_hash: str) -> bool:
    try:
        return _ph.check_needs_rehash(password_hash)
    except InvalidHashError:
        return True


def create_access_token(user_id: str, role: str, auth_version: int) -> tuple[str, str, datetime]:
    now = utcnow()
    expires = now + timedelta(minutes=settings.access_minutes)
    jti = secrets.token_urlsafe(18)
    payload: dict[str, Any] = {
        "sub": user_id,
        "role": role,
        "ver": auth_version,
        "type": "access",
        "jti": jti,
        "iss": settings.jwt_issuer,
        "iat": int(now.timestamp()),
        "exp": int(expires.timestamp()),
    }
    token = jwt.encode(payload, settings.effective_jwt_secret, algorithm="HS256")
    return token, jti, expires


def decode_access_token(token: str) -> dict[str, Any]:
    payload = jwt.decode(
        token,
        settings.effective_jwt_secret,
        algorithms=["HS256"],
        issuer=settings.jwt_issuer,
        options={"require": ["sub", "type", "jti", "ver", "exp", "iat", "iss"]},
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("Wrong token type")
    return payload


def create_refresh_token() -> tuple[str, str]:
    raw = secrets.token_urlsafe(48)
    return raw, hashlib.sha256(raw.encode()).hexdigest()


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_otp(mobile: str, challenge_id: str, code: str) -> str:
    msg = f"{challenge_id}:{mobile}:{code}".encode()
    return hmac.new(settings.effective_otp_pepper.encode(), msg, hashlib.sha256).hexdigest()


def verify_otp(code_hash: str, mobile: str, challenge_id: str, code: str) -> bool:
    return hmac.compare_digest(code_hash, hash_otp(mobile, challenge_id, code))
