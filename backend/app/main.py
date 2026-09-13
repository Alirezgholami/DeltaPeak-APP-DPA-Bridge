from __future__ import annotations

import json
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import desc, func, select, text, update
from sqlalchemy.orm import Session

from .config import settings
from .db import SessionLocal, init_db
from .jalali import jalali_datetime, utc_iso
from .models import AuditLog, OtpChallenge, RefreshSession, RevokedAccessToken, User
from .phone import is_valid_iran_mobile, normalize_iran_mobile
from .persian_normalizer import normalize_persian_text
from .schemas import (
    ChangePasswordRequest, LoginRequest, PasswordResetConfirm, PasswordResetRequest,
    RefreshRequest, RegisterConfirmRequest, RegisterOtpRequest, RegisterRequest,
)
from .security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    generate_otp,
    hash_otp,
    hash_password,
    hash_refresh_token,
    password_needs_rehash,
    utcnow,
    verify_otp,
    verify_password,
    verify_password_or_dummy,
)
from .sms import sms_provider

bearer = HTTPBearer(auto_error=False)


@asynccontextmanager
async def lifespan(_: FastAPI):
    if settings.env != "production":
        init_db()
    yield


app = FastAPI(title="DeltaPeak APP Backend", version="0.5.0", lifespan=lifespan)


@app.exception_handler(HTTPException)
async def http_error_handler(_: Request, exc: HTTPException):
    if isinstance(exc.detail, dict):
        body = exc.detail
    else:
        body = {"message": str(exc.detail), "code": "http_error"}
    return JSONResponse(status_code=exc.status_code, content=body, headers=exc.headers)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={"message": "اطلاعات ارسالی معتبر نیست.", "code": "validation_error", "errors": exc.errors()},
    )


def fail(status_code: int, message: str, code: str) -> None:
    raise HTTPException(status_code=status_code, detail={"message": message, "code": code})


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def client_ip(request: Request) -> str:
    # Uvicorn/reverse-proxy configuration is responsible for trusted proxy headers.
    # Do not trust a raw X-Forwarded-For value from arbitrary clients here.
    return (request.client.host if request.client else "unknown")[:64]


def audit(db: Session, action: str, request: Request, actor: User | None = None, target_type: str | None = None, target_id: str | None = None, details: dict[str, Any] | None = None) -> None:
    db.add(AuditLog(
        actor_user_id=actor.id if actor else None,
        action=action,
        target_type=target_type,
        target_id=target_id,
        request_ip=client_ip(request),
        details=json.dumps(details, ensure_ascii=False, separators=(",", ":")) if details else None,
    ))


def user_json(user: User) -> dict[str, Any]:
    return {
        "user_id": user.id,
        "display_name": user.display_name,
        "mobile": user.mobile,
        "username": user.username,
        "email": user.email,
        "status": user.status,
        "role": user.role,
        "created_at_utc": utc_iso(user.created_at),
        "created_at_jalali": jalali_datetime(user.created_at) or "",
        "last_login_at_utc": utc_iso(user.last_login_at),
        "last_login_at_jalali": jalali_datetime(user.last_login_at),
        "last_activity_at_utc": utc_iso(user.last_activity_at),
        "last_activity_at_jalali": jalali_datetime(user.last_activity_at),
    }


def issue_session(db: Session, user: User) -> dict[str, Any]:
    access_token, _, _ = create_access_token(user.id, user.role, user.auth_version)
    refresh_raw, refresh_hash = create_refresh_token()
    db.add(RefreshSession(
        user_id=user.id,
        token_hash=refresh_hash,
        expires_at=utcnow() + timedelta(days=settings.refresh_days),
    ))
    return {"access_token": access_token, "refresh_token": refresh_raw, "token_type": "bearer", "user": user_json(user)}


def get_current_token_payload(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict[str, Any]:
    if credentials is None:
        fail(401, "نشست کاربری معتبر نیست.", "not_authenticated")
    try:
        return decode_access_token(credentials.credentials)
    except jwt.ExpiredSignatureError:
        fail(401, "نشست کاربری منقضی شده است.", "token_expired")
    except jwt.InvalidTokenError:
        fail(401, "نشست کاربری معتبر نیست.", "invalid_token")
    raise AssertionError("unreachable")


def get_current_user(
    payload: dict[str, Any] = Depends(get_current_token_payload),
    db: Session = Depends(get_db),
) -> User:
    jti = str(payload["jti"])
    if db.get(RevokedAccessToken, jti) is not None:
        fail(401, "نشست کاربری پایان یافته است.", "token_revoked")
    user = db.get(User, str(payload["sub"]))
    if user is None or user.status != "active":
        fail(401, "حساب کاربری فعال نیست.", "account_inactive")
    if int(payload.get("ver", -1)) != user.auth_version:
        fail(401, "نشست کاربری نیاز به ورود مجدد دارد.", "token_superseded")
    user.last_activity_at = utcnow()
    db.commit()
    db.refresh(user)
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role not in {"admin", "owner"}:
        fail(403, "این بخش فقط برای Owner و Admin مجاز است.", "forbidden")
    return user


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "dpa-backend", "version": "0.5.0"}


@app.get("/ready")
def ready(db: Session = Depends(get_db)) -> dict[str, str]:
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        fail(503, "پایگاه داده آماده نیست.", "database_unavailable")
    return {"status": "ready", "service": "dpa-backend", "version": "0.5.0"}


@app.get("/v1/auth/me")
def me(user: User = Depends(get_current_user)):
    return {"user": user_json(user)}


@app.post("/v1/auth/activity")
def activity(user: User = Depends(get_current_user)):
    # get_current_user already updates last_activity_at. Heartbeats are intentionally
    # not written to AuditLog; otherwise a foreground app would create one audit row
    # every few minutes per user.
    return {"user": user_json(user)}


def _otp_cooldown_or_rate_limit(db: Session, *, mobile: str, purpose: str, ip: str) -> None:
    now = utcnow()
    recent = db.scalar(
        select(OtpChallenge)
        .where(OtpChallenge.mobile == mobile, OtpChallenge.purpose == purpose)
        .order_by(desc(OtpChallenge.created_at))
        .limit(1)
    )
    if recent is not None:
        resend_after = recent.resend_after_at
        if resend_after.tzinfo is None:
            resend_after = resend_after.replace(tzinfo=timezone.utc)
        if recent.consumed_at is None and resend_after > now:
            seconds = max(1, int((resend_after - now).total_seconds()))
            raise HTTPException(
                status_code=429,
                detail={"message": f"ارسال مجدد تا {seconds} ثانیه دیگر امکان‌پذیر است.", "code": "otp_cooldown"},
                headers={"Retry-After": str(seconds)},
            )
    if _count_recent_otp(db, mobile=mobile) >= settings.otp_mobile_hour_limit or _count_recent_otp(db, ip=ip) >= settings.otp_ip_hour_limit:
        fail(429, "تعداد درخواست‌ها زیاد است. کمی بعد دوباره تلاش کنید.", "otp_rate_limited")


def _new_otp_challenge(db: Session, *, mobile: str, purpose: str, ip: str) -> tuple[OtpChallenge, str]:
    now = utcnow()
    challenge = OtpChallenge(
        mobile=mobile,
        purpose=purpose,
        request_ip=ip,
        expires_at=now + timedelta(seconds=settings.otp_expire_seconds),
        resend_after_at=now + timedelta(seconds=settings.otp_resend_seconds),
        attempts_remaining=settings.otp_max_attempts,
        code_hash="pending",
    )
    db.add(challenge)
    db.flush()
    code = generate_otp()
    challenge.code_hash = hash_otp(mobile, challenge.id, code)
    return challenge, code


def _latest_otp(db: Session, *, mobile: str, purpose: str) -> OtpChallenge | None:
    return db.scalar(
        select(OtpChallenge)
        .where(OtpChallenge.mobile == mobile, OtpChallenge.purpose == purpose, OtpChallenge.consumed_at.is_(None))
        .order_by(desc(OtpChallenge.created_at))
        .limit(1)
    )


def _check_otp(db: Session, *, challenge: OtpChallenge | None, mobile: str, code: str, request: Request, fail_action: str) -> OtpChallenge:
    now = utcnow()
    if challenge is None:
        fail(400, "کد یک‌بارمصرف معتبر نیست.", "invalid_otp")
    expires = challenge.expires_at if challenge.expires_at.tzinfo else challenge.expires_at.replace(tzinfo=timezone.utc)
    if expires <= now or challenge.attempts_remaining <= 0:
        fail(400, "کد یک‌بارمصرف منقضی یا نامعتبر است.", "otp_expired")
    if not verify_otp(challenge.code_hash, mobile, challenge.id, code.strip()):
        challenge.attempts_remaining -= 1
        audit(db, fail_action, request, target_type="mobile", target_id=mobile)
        db.commit()
        fail(400, "کد یک‌بارمصرف صحیح نیست.", "invalid_otp")
    return challenge


@app.post("/v1/auth/register/request")
def register_request(body: RegisterOtpRequest, request: Request, db: Session = Depends(get_db)):
    mobile = normalize_iran_mobile(body.mobile)
    if not is_valid_iran_mobile(mobile):
        fail(400, "شماره موبایل معتبر نیست.", "invalid_mobile")
    if db.scalar(select(User.id).where(User.mobile == mobile)) is not None:
        fail(409, "این شماره موبایل قبلاً ثبت شده است.", "mobile_exists")
    ip = client_ip(request)
    _otp_cooldown_or_rate_limit(db, mobile=mobile, purpose="signup", ip=ip)
    _, code = _new_otp_challenge(db, mobile=mobile, purpose="signup", ip=ip)
    try:
        sms_provider.send_signup_code(mobile, code, settings.otp_expire_seconds)
    except Exception:
        db.rollback()
        fail(503, "ارسال پیامک در حال حاضر ممکن نیست. دوباره تلاش کنید.", "sms_unavailable")
    audit(db, "auth.signup_code_requested", request, target_type="mobile", target_id=mobile)
    db.commit()
    return {
        "message": "کد تأیید ثبت‌نام ارسال شد.",
        "expires_in_seconds": settings.otp_expire_seconds,
        "resend_after_seconds": settings.otp_resend_seconds,
    }


@app.post("/v1/auth/register/confirm", status_code=201)
def register_confirm(body: RegisterConfirmRequest, request: Request, db: Session = Depends(get_db)):
    mobile = normalize_iran_mobile(body.mobile)
    if not is_valid_iran_mobile(mobile):
        fail(400, "شماره موبایل معتبر نیست.", "invalid_mobile")
    display_name = normalize_persian_text(body.display_name)
    if not display_name:
        fail(400, "نام نمایشی الزامی است.", "invalid_display_name")
    if db.scalar(select(User.id).where((User.mobile == mobile) | (User.username == mobile))):
        fail(409, "این شماره موبایل قبلاً ثبت شده است.", "mobile_exists")
    challenge = _latest_otp(db, mobile=mobile, purpose="signup")
    challenge = _check_otp(
        db, challenge=challenge, mobile=mobile, code=body.code, request=request,
        fail_action="auth.signup_code_failed",
    )
    now = utcnow()
    challenge.consumed_at = now
    user = User(
        display_name=display_name,
        mobile=mobile,
        username=mobile,
        password_hash=hash_password(body.password),
        role="user",
        status="active",
        last_login_at=now,
        last_activity_at=now,
    )
    db.add(user)
    db.flush()
    audit(db, "auth.register", request, actor=user, target_type="user", target_id=user.id)
    session = issue_session(db, user)
    db.commit()
    return session


@app.post("/v1/auth/register", status_code=201)
def register_legacy(body: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    # Kept only for local development compatibility with pre-v0.5 clients.
    if settings.env == "production":
        fail(426, "ثبت‌نام امن نیاز به کد تأیید پیامکی دارد. اپ را به‌روز کنید.", "signup_otp_required")
    mobile = normalize_iran_mobile(body.mobile)
    username = normalize_iran_mobile(body.username or body.mobile)
    if not is_valid_iran_mobile(mobile) or username != mobile:
        fail(400, "شماره موبایل معتبر نیست.", "invalid_mobile")
    if db.scalar(select(User.id).where((User.mobile == mobile) | (User.username == username))):
        fail(409, "این شماره موبایل قبلاً ثبت شده است.", "mobile_exists")
    user = User(
        display_name=normalize_persian_text(body.display_name), mobile=mobile, username=mobile,
        password_hash=hash_password(body.password), role="user", status="active",
        last_login_at=utcnow(), last_activity_at=utcnow(),
    )
    db.add(user)
    db.flush()
    audit(db, "auth.register_legacy_dev", request, actor=user, target_type="user", target_id=user.id)
    session = issue_session(db, user)
    db.commit()
    return session


def _count_login_failures(db: Session, *, mobile: str | None = None, ip: str | None = None) -> int:
    since = utcnow() - timedelta(seconds=settings.login_window_seconds)
    stmt = select(func.count()).select_from(AuditLog).where(
        AuditLog.action == "auth.login_failed", AuditLog.created_at >= since
    )
    if mobile is not None:
        stmt = stmt.where(AuditLog.target_id == mobile)
    if ip is not None:
        stmt = stmt.where(AuditLog.request_ip == ip)
    return int(db.scalar(stmt) or 0)


def _enforce_login_rate_limit(db: Session, *, mobile: str | None, ip: str) -> None:
    blocked = _count_login_failures(db, ip=ip) >= settings.login_ip_max_failures
    if mobile is not None:
        blocked = blocked or _count_login_failures(db, mobile=mobile) >= settings.login_mobile_max_failures
    if blocked:
        seconds = max(60, settings.login_window_seconds)
        raise HTTPException(
            status_code=429,
            detail={"message": "تلاش‌های ورود بیش از حد مجاز است. کمی بعد دوباره تلاش کنید.", "code": "login_rate_limited"},
            headers={"Retry-After": str(seconds)},
        )


@app.post("/v1/auth/login")
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    identity = normalize_iran_mobile(body.mobile or body.username or "")
    ip = client_ip(request)
    valid_identity = is_valid_iran_mobile(identity)
    _enforce_login_rate_limit(db, mobile=identity if valid_identity else None, ip=ip)
    if not valid_identity:
        audit(db, "auth.login_failed", request, target_type="mobile", target_id=None)
        db.commit()
        fail(401, "شماره موبایل یا رمز عبور صحیح نیست.", "invalid_credentials")
    user = db.scalar(select(User).where(User.mobile == identity))
    password_ok = verify_password_or_dummy(user.password_hash if user is not None else None, body.password)
    if user is None or user.status != "active" or not password_ok:
        audit(db, "auth.login_failed", request, target_type="mobile", target_id=identity)
        db.commit()
        fail(401, "شماره موبایل یا رمز عبور صحیح نیست.", "invalid_credentials")
    if password_needs_rehash(user.password_hash):
        user.password_hash = hash_password(body.password)
    user.last_login_at = utcnow()
    user.last_activity_at = user.last_login_at
    audit(db, "auth.login", request, actor=user, target_type="user", target_id=user.id)
    session = issue_session(db, user)
    db.commit()
    return session


@app.post("/v1/auth/logout")
def logout(
    request: Request,
    payload: dict[str, Any] = Depends(get_current_token_payload),
    db: Session = Depends(get_db),
):
    user_id = str(payload["sub"])
    jti = str(payload["jti"])
    exp = datetime.fromtimestamp(int(payload["exp"]), tz=timezone.utc)
    if db.get(RevokedAccessToken, jti) is None:
        db.add(RevokedAccessToken(jti=jti, user_id=user_id, expires_at=exp))
    db.execute(
        update(RefreshSession)
        .where(RefreshSession.user_id == user_id, RefreshSession.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )
    user = db.get(User, user_id)
    audit(db, "auth.logout", request, actor=user, target_type="user", target_id=user_id)
    db.commit()
    return {"ok": True}


@app.post("/v1/auth/refresh")
def refresh(body: RefreshRequest, request: Request, db: Session = Depends(get_db)):
    token_hash = hash_refresh_token(body.refresh_token)
    row = db.scalar(select(RefreshSession).where(RefreshSession.token_hash == token_hash))
    if row is None or row.revoked_at is not None or row.expires_at.replace(tzinfo=timezone.utc) <= utcnow():
        fail(401, "نشست کاربری معتبر نیست.", "invalid_refresh_token")
    user = db.get(User, row.user_id)
    if user is None or user.status != "active":
        fail(401, "حساب کاربری فعال نیست.", "account_inactive")
    row.revoked_at = utcnow()  # refresh-token rotation
    user.last_activity_at = utcnow()
    audit(db, "auth.refresh", request, actor=user, target_type="user", target_id=user.id)
    result = issue_session(db, user)
    db.commit()
    return result


@app.post("/v1/auth/change-password")
def change_password(
    body: ChangePasswordRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(user.password_hash, body.current_password):
        fail(400, "رمز عبور فعلی صحیح نیست.", "wrong_current_password")
    user.password_hash = hash_password(body.new_password)
    user.auth_version += 1
    db.execute(
        update(RefreshSession)
        .where(RefreshSession.user_id == user.id, RefreshSession.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )
    audit(db, "auth.password_changed", request, actor=user, target_type="user", target_id=user.id)
    session = issue_session(db, user)
    db.commit()
    return session


def _count_recent_otp(db: Session, *, mobile: str | None = None, ip: str | None = None) -> int:
    since = utcnow() - timedelta(hours=1)
    stmt = select(func.count()).select_from(OtpChallenge).where(OtpChallenge.created_at >= since)
    if mobile is not None:
        stmt = stmt.where(OtpChallenge.mobile == mobile)
    if ip is not None:
        stmt = stmt.where(OtpChallenge.request_ip == ip)
    return int(db.scalar(stmt) or 0)


@app.post("/v1/auth/password-reset/request")
def password_reset_request(body: PasswordResetRequest, request: Request, db: Session = Depends(get_db)):
    mobile = normalize_iran_mobile(body.mobile)
    if not is_valid_iran_mobile(mobile):
        fail(400, "شماره موبایل معتبر نیست.", "invalid_mobile")
    ip = client_ip(request)
    _otp_cooldown_or_rate_limit(db, mobile=mobile, purpose="password_reset", ip=ip)
    user_exists = db.scalar(select(User.id).where(User.mobile == mobile, User.status == "active")) is not None

    # Create a challenge even for an unknown account so cooldown/hourly limits cannot
    # be bypassed by repeatedly targeting numbers that are not registered.
    _, code = _new_otp_challenge(db, mobile=mobile, purpose="password_reset", ip=ip)
    if user_exists:
        try:
            sms_provider.send_reset_code(mobile, code, settings.otp_expire_seconds)
        except Exception:
            db.rollback()
            fail(503, "ارسال پیامک در حال حاضر ممکن نیست. دوباره تلاش کنید.", "sms_unavailable")
        audit(db, "auth.password_reset_requested", request, target_type="mobile", target_id=mobile)
    else:
        audit(db, "auth.password_reset_requested_unknown", request, target_type="mobile", target_id=mobile)
    db.commit()
    return {
        "message": "اگر حسابی با این شماره وجود داشته باشد، کد بازیابی ارسال می‌شود.",
        "expires_in_seconds": settings.otp_expire_seconds,
        "resend_after_seconds": settings.otp_resend_seconds,
    }


@app.post("/v1/auth/password-reset/confirm")
def password_reset_confirm(body: PasswordResetConfirm, request: Request, db: Session = Depends(get_db)):
    mobile = normalize_iran_mobile(body.mobile)
    if not is_valid_iran_mobile(mobile):
        fail(400, "کد یا درخواست بازیابی معتبر نیست.", "invalid_reset")
    challenge = _latest_otp(db, mobile=mobile, purpose="password_reset")
    challenge = _check_otp(
        db, challenge=challenge, mobile=mobile, code=body.code, request=request,
        fail_action="auth.password_reset_code_failed",
    )
    now = utcnow()
    user = db.scalar(select(User).where(User.mobile == mobile, User.status == "active"))
    if user is None:
        challenge.consumed_at = now
        db.commit()
        fail(400, "کد یا درخواست بازیابی معتبر نیست.", "invalid_reset")
    challenge.consumed_at = now
    user.password_hash = hash_password(body.new_password)
    user.auth_version += 1
    user.last_activity_at = now
    db.execute(
        update(RefreshSession)
        .where(RefreshSession.user_id == user.id, RefreshSession.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    audit(db, "auth.password_reset_completed", request, actor=user, target_type="user", target_id=user.id)
    db.commit()
    return {"ok": True, "message": "رمز عبور تغییر کرد."}


@app.get("/v1/admin/users")
def list_users(
    request: Request,
    limit: int = 100,
    sort: str = "newest",
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    limit = max(1, min(limit, 200))
    if sort == "last_activity":
        order = (User.last_activity_at.is_(None), desc(User.last_activity_at), desc(User.created_at))
    else:
        order = (desc(User.created_at),)
    users = list(db.scalars(select(User).order_by(*order).limit(limit)).all())
    audit(db, "admin.users_listed", request, actor=admin, target_type="user_collection", details={"limit": limit, "sort": sort})
    db.commit()
    return {"users": [user_json(user) for user in users]}
