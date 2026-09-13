from __future__ import annotations

import os
import secrets
from dataclasses import dataclass


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    env: str = os.getenv("DPA_ENV", "development").lower()
    database_url: str = os.getenv("DPA_DATABASE_URL", "sqlite:///./dpa_backend.db")
    jwt_secret: str = os.getenv("DPA_JWT_SECRET", "")
    jwt_issuer: str = os.getenv("DPA_JWT_ISSUER", "dpa-backend")
    access_minutes: int = _int("DPA_ACCESS_TOKEN_MINUTES", 30)
    refresh_days: int = _int("DPA_REFRESH_TOKEN_DAYS", 30)
    otp_expire_seconds: int = _int("DPA_OTP_EXPIRE_SECONDS", 120)
    otp_resend_seconds: int = _int("DPA_OTP_RESEND_SECONDS", 60)
    otp_max_attempts: int = _int("DPA_OTP_MAX_ATTEMPTS", 5)
    otp_mobile_hour_limit: int = _int("DPA_OTP_MOBILE_HOUR_LIMIT", 6)
    otp_ip_hour_limit: int = _int("DPA_OTP_IP_HOUR_LIMIT", 30)
    login_window_seconds: int = _int("DPA_LOGIN_WINDOW_SECONDS", 900)
    login_mobile_max_failures: int = _int("DPA_LOGIN_MOBILE_MAX_FAILURES", 5)
    login_ip_max_failures: int = _int("DPA_LOGIN_IP_MAX_FAILURES", 25)
    otp_pepper: str = os.getenv("DPA_OTP_PEPPER", "")
    sms_provider: str = os.getenv("DPA_SMS_PROVIDER", "console").lower()
    sms_webhook_url: str = os.getenv("DPA_SMS_WEBHOOK_URL", "")
    sms_webhook_token: str = os.getenv("DPA_SMS_WEBHOOK_TOKEN", "")
    sms_template: str = os.getenv("DPA_SMS_TEMPLATE", "DPA_OTP")
    sms_signup_template: str = os.getenv("DPA_SMS_SIGNUP_TEMPLATE", os.getenv("DPA_SMS_TEMPLATE", "DPA_SIGNUP"))
    sms_reset_template: str = os.getenv("DPA_SMS_RESET_TEMPLATE", os.getenv("DPA_SMS_TEMPLATE", "DPA_RESET"))
    kavenegar_api_key: str = os.getenv("DPA_KAVENEGAR_API_KEY", "")
    kavenegar_template: str = os.getenv("DPA_KAVENEGAR_TEMPLATE", "")
    kavenegar_signup_template: str = os.getenv("DPA_KAVENEGAR_SIGNUP_TEMPLATE", os.getenv("DPA_KAVENEGAR_TEMPLATE", ""))
    kavenegar_reset_template: str = os.getenv("DPA_KAVENEGAR_RESET_TEMPLATE", os.getenv("DPA_KAVENEGAR_TEMPLATE", ""))

    def validated(self) -> "Settings":
        allowed_sms = {"console", "memory", "webhook", "kavenegar"}
        if self.sms_provider not in allowed_sms:
            raise RuntimeError(f"Unsupported DPA_SMS_PROVIDER: {self.sms_provider}")
        if self.env == "production":
            if len(self.jwt_secret) < 32:
                raise RuntimeError("DPA_JWT_SECRET must be at least 32 characters in production.")
            if len(self.otp_pepper) < 32:
                raise RuntimeError("DPA_OTP_PEPPER must be at least 32 characters in production.")
            if self.sms_provider in {"console", "memory"}:
                raise RuntimeError("A real SMS provider is required in production.")
            if self.sms_provider == "webhook" and not self.sms_webhook_url:
                raise RuntimeError("DPA_SMS_WEBHOOK_URL is required for webhook SMS in production.")
            if self.sms_provider == "kavenegar":
                if not self.kavenegar_api_key:
                    raise RuntimeError("DPA_KAVENEGAR_API_KEY is required for Kavenegar SMS in production.")
                if not self.kavenegar_signup_template:
                    raise RuntimeError("DPA_KAVENEGAR_SIGNUP_TEMPLATE (or DPA_KAVENEGAR_TEMPLATE) is required in production.")
                if not self.kavenegar_reset_template:
                    raise RuntimeError("DPA_KAVENEGAR_RESET_TEMPLATE (or DPA_KAVENEGAR_TEMPLATE) is required in production.")
        return self

    @property
    def effective_jwt_secret(self) -> str:
        if self.jwt_secret:
            return self.jwt_secret
        # Development-only ephemeral secret. Production validation rejects this.
        return _DEV_JWT_SECRET

    @property
    def effective_otp_pepper(self) -> str:
        if self.otp_pepper:
            return self.otp_pepper
        return _DEV_OTP_PEPPER


_DEV_JWT_SECRET = secrets.token_urlsafe(48)
_DEV_OTP_PEPPER = secrets.token_urlsafe(48)
settings = Settings().validated()
