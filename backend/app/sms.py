from __future__ import annotations

from abc import ABC, abstractmethod

import httpx

from .config import settings


_PURPOSE_MESSAGES = {
    "signup": "کد تأیید ثبت‌نام Delta Peak",
    "password_reset": "کد بازیابی رمز Delta Peak",
}


class SmsProvider(ABC):
    @abstractmethod
    def send_code(self, mobile: str, code: str, expires_in_seconds: int, purpose: str) -> None:
        raise NotImplementedError

    def send_reset_code(self, mobile: str, code: str, expires_in_seconds: int) -> None:
        self.send_code(mobile, code, expires_in_seconds, "password_reset")

    def send_signup_code(self, mobile: str, code: str, expires_in_seconds: int) -> None:
        self.send_code(mobile, code, expires_in_seconds, "signup")


class ConsoleSmsProvider(SmsProvider):
    def send_code(self, mobile: str, code: str, expires_in_seconds: int, purpose: str) -> None:
        print(f"[DPA DEV SMS] {mobile}: purpose={purpose}, code={code}, expires={expires_in_seconds}s")


class MemorySmsProvider(SmsProvider):
    latest_codes: dict[str, str] = {}
    latest_by_purpose: dict[tuple[str, str], str] = {}

    def send_code(self, mobile: str, code: str, expires_in_seconds: int, purpose: str) -> None:
        del expires_in_seconds
        if settings.env != "test":
            raise RuntimeError("Memory SMS provider is test-only.")
        self.latest_codes[mobile] = code
        self.latest_by_purpose[(mobile, purpose)] = code


class WebhookSmsProvider(SmsProvider):
    def send_code(self, mobile: str, code: str, expires_in_seconds: int, purpose: str) -> None:
        if not settings.sms_webhook_url:
            raise RuntimeError("DPA_SMS_WEBHOOK_URL is not configured.")
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        if settings.sms_webhook_token:
            headers["Authorization"] = f"Bearer {settings.sms_webhook_token}"
        template = settings.sms_signup_template if purpose == "signup" else settings.sms_reset_template
        label = _PURPOSE_MESSAGES.get(purpose, "کد یک‌بارمصرف Delta Peak")
        payload = {
            "to": mobile,
            "purpose": purpose,
            "template": template,
            "code": code,
            "expires_in_seconds": expires_in_seconds,
            "message": f"{label}: {code}",
        }
        with httpx.Client(timeout=10.0) as client:
            response = client.post(settings.sms_webhook_url, json=payload, headers=headers)
            response.raise_for_status()


class KavenegarSmsProvider(SmsProvider):
    """Direct Kavenegar VerifyLookup adapter for Iranian OTP delivery."""

    @staticmethod
    def _local_mobile(mobile: str) -> str:
        if mobile.startswith("+98"):
            return "0" + mobile[3:]
        return mobile

    def _template(self, purpose: str) -> str:
        if purpose == "signup":
            return settings.kavenegar_signup_template
        return settings.kavenegar_reset_template

    def send_code(self, mobile: str, code: str, expires_in_seconds: int, purpose: str) -> None:
        del expires_in_seconds
        template = self._template(purpose)
        if not settings.kavenegar_api_key or not template:
            raise RuntimeError("Kavenegar SMS is not fully configured.")
        url = f"https://api.kavenegar.com/v1/{settings.kavenegar_api_key}/verify/lookup.json"
        payload = {
            "receptor": self._local_mobile(mobile),
            "template": template,
            "token": code,
            "type": "sms",
        }
        try:
            with httpx.Client(timeout=10.0) as client:
                response = client.post(url, data=payload, headers={"Accept": "application/json"})
                response.raise_for_status()
                result = response.json()
        except Exception as exc:
            raise RuntimeError("Kavenegar request failed.") from exc
        returned = result.get("return") if isinstance(result, dict) else None
        if not isinstance(returned, dict) or int(returned.get("status", 0)) != 200:
            raise RuntimeError("Kavenegar rejected the OTP request.")


def build_sms_provider() -> SmsProvider:
    if settings.sms_provider == "webhook":
        return WebhookSmsProvider()
    if settings.sms_provider == "memory":
        return MemorySmsProvider()
    if settings.sms_provider == "kavenegar":
        return KavenegarSmsProvider()
    if settings.sms_provider == "console":
        return ConsoleSmsProvider()
    raise RuntimeError(f"Unsupported SMS provider: {settings.sms_provider}")


sms_provider = build_sms_provider()
