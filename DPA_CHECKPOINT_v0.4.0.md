# DPA v0.4.0+6 Checkpoint

Scope: Production-ready account backend foundation + automatic mobile session refresh, preserving all DPA v0.3.0 features and DPD v3.88 data.

## Preserved from v0.3.0

- Offline-first DPD v3.88 peak/route database, 1999 publishable peaks and exactly 31 official provinces.
- Register/Login/Logout UI with Iranian mobile number as username.
- Change/reset password UI, OTP resend timer, user/admin/owner model and admin/owner user list.
- System/Light/Dark theme persistence.
- Peak labels `ارتفاع قله (تابلو)` and `ارتفاع قله (Map)`.
- Organic Maps links, favorites, filters, stats, soft delete/restore, audit history, backup/restore/import/export, private GPX storage and data-quality flags.

## Added in v0.4.0

- `backend/` FastAPI reference implementation matching the mobile client.
- SQLite development + PostgreSQL production database support.
- Argon2id password hashing.
- Short-lived JWT access tokens and rotating refresh tokens.
- Flutter automatic refresh/retry for authenticated requests.
- Password change returns a fresh session rather than forcing an unnecessary logout.
- Password change/reset invalidates older access-token generations and revokes old refresh sessions.
- Password-reset OTP: HMAC verifier only, expiry, resend cooldown, max attempts, per-mobile/IP hourly rate limits and replay prevention.
- Replaceable SMS provider layer: console development, memory tests, HTTPS webhook production.
- Server-enforced `user/admin/owner` authorization.
- User newest/last-activity sorting with UTC + Jalali/Tehran API timestamps.
- Security audit log and first-owner bootstrap command with no default password.
- Dockerfile + PostgreSQL Docker Compose reference with Alembic migration-on-start.
- GitHub Android workflow now includes the backend auth test gate.

## Validation performed

Backend automated test suite passes for phone normalization, Jalali conversion, register/login, reset OTP, role enforcement and logout/token revocation. Flutter source was statically reviewed in this environment; a Flutter SDK is not installed locally, so the definitive `flutter analyze`, `flutter test` and APK build remain CI gates.

## Remaining external setup before live accounts

1. Choose/deploy an HTTPS host for `backend/` with PostgreSQL.
2. Choose the Iranian SMS provider or connect an adapter to the generic DPA SMS webhook.
3. Configure production secrets (`DPA_JWT_SECRET`, `DPA_OTP_PEPPER`, DB and SMS credentials).
4. Create the first Owner using `python -m app.bootstrap_owner`.
5. Set repository secret `DPA_API_BASE_URL` to the deployed HTTPS API and run the Android build workflow.
