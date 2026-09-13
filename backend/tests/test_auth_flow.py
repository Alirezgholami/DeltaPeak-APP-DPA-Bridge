import importlib
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient


def _load_app(tmp_path: Path, **extra_env):
    os.environ["DPA_ENV"] = "test"
    os.environ["DPA_DATABASE_URL"] = f"sqlite:///{tmp_path / 'test.db'}"
    os.environ["DPA_SMS_PROVIDER"] = "memory"
    os.environ["DPA_JWT_SECRET"] = "test-jwt-secret-abcdefghijklmnopqrstuvwxyz123456"
    os.environ["DPA_OTP_PEPPER"] = "test-otp-pepper-abcdefghijklmnopqrstuvwxyz1234"
    for key, value in extra_env.items():
        os.environ[key] = str(value)
    for name in list(sys.modules):
        if name == "app" or name.startswith("app."):
            del sys.modules[name]
    main = importlib.import_module("app.main")
    sms = importlib.import_module("app.sms")
    db = importlib.import_module("app.db")
    models = importlib.import_module("app.models")
    return main, sms, db, models


def _signup(client, sms, mobile="09121234567", password="StrongPass123"):
    r = client.post("/v1/auth/register/request", json={"mobile": mobile, "resend": False})
    assert r.status_code == 200, r.text
    code = sms.MemorySmsProvider.latest_by_purpose[("+989121234567", "signup")]
    r = client.post(
        "/v1/auth/register/confirm",
        json={"display_name": "Ali", "mobile": mobile, "code": code, "password": password},
    )
    assert r.status_code == 201, r.text
    return r


def test_signup_login_change_reset_refresh_and_admin(tmp_path):
    main, sms, dbmod, models = _load_app(tmp_path)
    with TestClient(main.app) as client:
        r = client.get("/health")
        assert r.status_code == 200 and r.json()["version"] == "0.5.0"
        r = client.get("/ready")
        assert r.status_code == 200

        r = _signup(client, sms)
        old_access = r.json()["access_token"]
        old_refresh = r.json()["refresh_token"]
        assert r.json()["user"]["mobile"] == "+989121234567"

        # Re-registering the same verified number is blocked.
        r = client.post("/v1/auth/register/request", json={"mobile": "09121234567", "resend": False})
        assert r.status_code == 409

        r = client.post("/v1/auth/login", json={"mobile": "09121234567", "password": "StrongPass123"})
        assert r.status_code == 200, r.text
        access = r.json()["access_token"]

        r = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {access}"})
        assert r.status_code == 200, r.text
        assert r.json()["user"]["mobile"] == "+989121234567"
        r = client.post("/v1/auth/activity", headers={"Authorization": f"Bearer {access}"})
        assert r.status_code == 200, r.text
        assert r.json()["user"]["last_activity_at_utc"] is not None

        r = client.post(
            "/v1/auth/change-password",
            headers={"Authorization": f"Bearer {access}"},
            json={"current_password": "StrongPass123", "new_password": "ChangedPass123"},
        )
        assert r.status_code == 200, r.text
        changed_access = r.json()["access_token"]
        changed_refresh = r.json()["refresh_token"]
        assert changed_access and changed_refresh
        r = client.get("/v1/admin/users", headers={"Authorization": f"Bearer {old_access}"})
        assert r.status_code == 401
        r = client.post("/v1/auth/refresh", json={"refresh_token": old_refresh})
        assert r.status_code == 401

        r = client.post("/v1/auth/refresh", json={"refresh_token": changed_refresh})
        assert r.status_code == 200, r.text
        rotated_access = r.json()["access_token"]
        rotated_refresh = r.json()["refresh_token"]
        r = client.post("/v1/auth/refresh", json={"refresh_token": changed_refresh})
        assert r.status_code == 401
        assert rotated_refresh != changed_refresh

        r = client.post("/v1/auth/password-reset/request", json={"mobile": "09121234567", "resend": False})
        assert r.status_code == 200, r.text
        code = sms.MemorySmsProvider.latest_by_purpose[("+989121234567", "password_reset")]
        r = client.post(
            "/v1/auth/password-reset/confirm",
            json={"mobile": "09121234567", "code": code, "new_password": "NewStrongPass123"},
        )
        assert r.status_code == 200, r.text
        r = client.get("/v1/admin/users", headers={"Authorization": f"Bearer {rotated_access}"})
        assert r.status_code == 401

        r = client.post("/v1/auth/login", json={"mobile": "09121234567", "password": "NewStrongPass123"})
        assert r.status_code == 200, r.text
        token = r.json()["access_token"]
        r = client.get("/v1/admin/users", headers={"Authorization": f"Bearer {token}"})
        assert r.status_code == 403

        with dbmod.SessionLocal() as db:
            user = db.query(models.User).filter_by(mobile="+989121234567").one()
            user.role = "owner"
            db.commit()
        r = client.post("/v1/auth/login", json={"mobile": "09121234567", "password": "NewStrongPass123"})
        owner_token = r.json()["access_token"]
        r = client.get("/v1/admin/users?sort=last_activity", headers={"Authorization": f"Bearer {owner_token}"})
        assert r.status_code == 200, r.text
        assert len(r.json()["users"]) == 1

        r = client.post("/v1/auth/logout", headers={"Authorization": f"Bearer {owner_token}"})
        assert r.status_code == 200, r.text
        r = client.get("/v1/admin/users", headers={"Authorization": f"Bearer {owner_token}"})
        assert r.status_code == 401


def test_login_rate_limit_and_unknown_reset_cooldown(tmp_path):
    main, sms, _, _ = _load_app(
        tmp_path,
        DPA_LOGIN_MOBILE_MAX_FAILURES=2,
        DPA_LOGIN_IP_MAX_FAILURES=20,
        DPA_LOGIN_WINDOW_SECONDS=900,
    )
    with TestClient(main.app) as client:
        _signup(client, sms)
        for _ in range(2):
            r = client.post("/v1/auth/login", json={"mobile": "09121234567", "password": "wrong"})
            assert r.status_code == 401
        r = client.post("/v1/auth/login", json={"mobile": "09121234567", "password": "StrongPass123"})
        assert r.status_code == 429 and r.json()["code"] == "login_rate_limited"

        r = client.post("/v1/auth/password-reset/request", json={"mobile": "09129999999", "resend": False})
        assert r.status_code == 200
        r = client.post("/v1/auth/password-reset/request", json={"mobile": "09129999999", "resend": True})
        assert r.status_code == 429 and r.json()["code"] == "otp_cooldown"
