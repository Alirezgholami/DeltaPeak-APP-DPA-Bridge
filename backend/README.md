# DPA Backend v0.5.0

Production-oriented account backend for DeltaPeak APP. Peak/route reference data remains offline-first inside the Flutter application; identity, sessions and administrative account data are authoritative on this backend.

## Security/account contract

- Iranian mobile number is the canonical username (`+989xxxxxxxxx`).
- Sign-up requires mobile ownership verification with an OTP before the account is created.
- Login has per-mobile and per-IP failed-attempt rate limits and constant-cost Argon2 verification for unknown users.
- Passwords use Argon2id.
- JWT access tokens are short-lived; opaque refresh tokens rotate on use.
- Password change/reset increments `auth_version`, invalidating older access/refresh sessions.
- Password reset OTP has expiry, resend cooldown, maximum attempts, per-mobile/IP hourly limits and replay prevention.
- SMS provider abstraction: console/memory for development/test; generic HTTPS webhook or Kavenegar VerifyLookup for production.
- Server-enforced `user`, `admin`, `owner` roles.
- Admin/Owner can list users sorted by newest or last activity.
- `/v1/auth/me` revalidates the cached mobile session; `/v1/auth/activity` updates last activity.
- UTC authoritative timestamps plus Jalali/Tehran display timestamps.
- Security audit log.

## Data/deployment

- SQLite for local development/test.
- PostgreSQL + Alembic for production.
- Docker runs the API as an unprivileged user, read-only filesystem, dropped Linux capabilities.
- Production Compose does not expose API port 8080 to the host; Caddy is the public TLS reverse proxy.
- `/health` = process health; `/ready` = API + database readiness.
- Caddy terminates HTTPS and proxies internally to FastAPI.

## Development

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8080
```

Tests:

```bash
PYTHONPATH=. pytest -q
```

## Production

See `DEPLOY_PRODUCTION.md`.

Generate a production env with independent random secrets:

```bash
python scripts/init_production_env.py --output .env.production
```

Then edit the API domain and SMS credentials/templates and run:

```bash
python scripts/production_preflight.py .env.production
./scripts/deploy_production.sh .env.production
```
