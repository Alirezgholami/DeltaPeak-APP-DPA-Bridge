import importlib
import os
import sys


def _load_sms():
    os.environ["DPA_ENV"] = "test"
    os.environ["DPA_SMS_PROVIDER"] = "kavenegar"
    os.environ["DPA_KAVENEGAR_API_KEY"] = "secret-key"
    os.environ["DPA_KAVENEGAR_SIGNUP_TEMPLATE"] = "dpa-signup"
    os.environ["DPA_KAVENEGAR_RESET_TEMPLATE"] = "dpa-reset"
    os.environ.pop("DPA_KAVENEGAR_TEMPLATE", None)
    for name in list(sys.modules):
        if name == "app" or name.startswith("app."):
            del sys.modules[name]
    return importlib.import_module("app.sms")


def test_kavenegar_verify_lookup_payload(monkeypatch):
    sms = _load_sms()
    calls = []

    class Response:
        def raise_for_status(self):
            return None
        def json(self):
            return {"return": {"status": 200, "message": "ok"}, "entries": [{"messageid": 1}]}

    class Client:
        def __init__(self, *args, **kwargs):
            pass
        def __enter__(self):
            return self
        def __exit__(self, *args):
            return False
        def post(self, url, data=None, headers=None):
            calls.append({"url": url, "data": data, "headers": headers})
            return Response()

    monkeypatch.setattr(sms.httpx, "Client", Client)
    provider = sms.KavenegarSmsProvider()
    provider.send_signup_code("+989121234567", "111111", 120)
    provider.send_reset_code("+989121234567", "222222", 120)

    assert calls[0]["data"] == {
        "receptor": "09121234567", "template": "dpa-signup", "token": "111111", "type": "sms"
    }
    assert calls[1]["data"] == {
        "receptor": "09121234567", "template": "dpa-reset", "token": "222222", "type": "sms"
    }
    assert "/v1/secret-key/verify/lookup.json" in calls[0]["url"]
