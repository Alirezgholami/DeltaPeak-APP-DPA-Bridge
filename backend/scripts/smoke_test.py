from __future__ import annotations

import argparse
import json
import ssl
import urllib.request


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "DPA-production-smoke/0.5.0"})
    with urllib.request.urlopen(req, timeout=15, context=ssl.create_default_context()) as r:
        if r.status != 200:
            raise SystemExit(f"HTTP {r.status}: {url}")
        return json.loads(r.read().decode("utf-8"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("base_url")
    args = ap.parse_args()
    base = args.base_url.rstrip("/")
    if not base.startswith("https://"):
        raise SystemExit("Production smoke test requires an https:// URL")
    health = get_json(base + "/health")
    ready = get_json(base + "/ready")
    if health.get("status") != "ok" or ready.get("status") != "ready":
        raise SystemExit("Health/readiness response did not pass")
    print("DPA PRODUCTION SMOKE PASSED")
    print(f"  service version: {health.get('version')}")
    print("  TLS + API + database: reachable")


if __name__ == "__main__":
    main()
