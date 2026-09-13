from __future__ import annotations

import argparse
from pathlib import Path
from urllib.parse import urlparse


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def fail(message: str) -> None:
    raise SystemExit(f"DPA PRODUCTION PREFLIGHT FAILED: {message}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("env_file", nargs="?", default=".env.production")
    args = ap.parse_args()
    path = Path(args.env_file)
    if not path.exists():
        fail(f"missing {path}")
    env = read_env(path)

    domain = env.get("DPA_API_DOMAIN", "")
    if not domain or domain == "api.example.com" or "://" in domain or "/" in domain:
        fail("DPA_API_DOMAIN must be a real hostname, without https:// or a path")
    for key, minimum in (("DPA_POSTGRES_PASSWORD", 24), ("DPA_JWT_SECRET", 32), ("DPA_OTP_PEPPER", 32)):
        if len(env.get(key, "")) < minimum:
            fail(f"{key} is missing or too short")

    provider = env.get("DPA_SMS_PROVIDER", "kavenegar").lower()
    if provider == "kavenegar":
        if not env.get("DPA_KAVENEGAR_API_KEY"):
            fail("DPA_KAVENEGAR_API_KEY is required")
        common = env.get("DPA_KAVENEGAR_TEMPLATE", "")
        if not (env.get("DPA_KAVENEGAR_SIGNUP_TEMPLATE") or common):
            fail("Kavenegar signup template is required")
        if not (env.get("DPA_KAVENEGAR_RESET_TEMPLATE") or common):
            fail("Kavenegar reset template is required")
    elif provider == "webhook":
        u = urlparse(env.get("DPA_SMS_WEBHOOK_URL", ""))
        if u.scheme != "https" or not u.netloc:
            fail("DPA_SMS_WEBHOOK_URL must be HTTPS in production")
    else:
        fail("DPA_SMS_PROVIDER must be kavenegar or webhook in production")

    print("DPA PRODUCTION PREFLIGHT PASSED")
    print(f"  domain: {domain}")
    print(f"  SMS provider: {provider}")
    print("  secrets: present (values intentionally not printed)")


if __name__ == "__main__":
    main()
