from __future__ import annotations

import argparse
import secrets
from pathlib import Path


def replace_value(text: str, key: str, value: str) -> str:
    lines = text.splitlines()
    prefix = f"{key}="
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            lines[i] = prefix + value
            return "\n".join(lines) + "\n"
    return text + f"{key}={value}\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a DPA production env file with strong generated secrets.")
    parser.add_argument("--output", default=".env.production")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    template = root / ".env.production.example"
    output = Path(args.output)
    if not output.is_absolute():
        output = root / output
    if output.exists() and not args.force:
        raise SystemExit(f"Refusing to overwrite {output}. Use --force only if you intend to rotate secrets.")

    text = template.read_text(encoding="utf-8")
    text = replace_value(text, "DPA_JWT_SECRET", secrets.token_urlsafe(48))
    text = replace_value(text, "DPA_OTP_PEPPER", secrets.token_urlsafe(48))
    text = replace_value(text, "DPA_POSTGRES_PASSWORD", secrets.token_urlsafe(32))
    output.write_text(text, encoding="utf-8")
    try:
        output.chmod(0o600)
    except OSError:
        pass
    print(f"Created {output}")
    print("Edit DPA_API_DOMAIN and SMS provider credentials/templates before deployment.")


if __name__ == "__main__":
    main()
