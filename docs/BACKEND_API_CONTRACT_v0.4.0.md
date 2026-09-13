# DPA v0.4.0 Backend/Auth Contract

DPA keeps peak/route reference data offline-first in SQLite. Identity, password recovery, authorization, authoritative account activity, session revocation and security audit live on the central backend.

## Identity and roles

- Username is the normalized Iranian mobile number in E.164 form, e.g. `+989121234567`.
- Roles: `user`, `admin`, `owner`.
- Server authorization is mandatory. Hiding controls in Flutter is never the authorization boundary.
- Passwords are hashed with Argon2id and are never stored/logged in plaintext.
- Access tokens are short-lived JWTs. Refresh tokens are random, rotated and stored server-side only as SHA-256 hashes.
- Password change/reset increments a per-user auth version, immediately invalidating older access tokens; existing refresh sessions are revoked.
- Android stores access/refresh tokens only in OS secure storage. They never enter SQLite backup/export.

## Endpoints used by the app

- `POST /v1/auth/register` — `display_name`, `mobile`, `username`, `password`
- `POST /v1/auth/login` — `mobile`, `username`, `password`
- `POST /v1/auth/logout` — bearer access token
- `POST /v1/auth/refresh` — `refresh_token`; rotates refresh token and returns a fresh session
- `POST /v1/auth/change-password` — bearer token, `current_password`, `new_password`; returns a fresh session
- `POST /v1/auth/password-reset/request` — `mobile`, `resend`; generic response with `expires_in_seconds`, `resend_after_seconds`
- `POST /v1/auth/password-reset/confirm` — `mobile`, `code`, `new_password`
- `GET /v1/admin/users?limit=200&sort=newest|last_activity` — server-enforced admin/owner only
- `GET /health` — deployment health check

Successful login/register/refresh/change-password responses contain `access_token`, `refresh_token`, `token_type` and `user`. The `user` object includes:
`user_id`, `display_name`, `mobile`, `username`, `email`, `status`, `role`, UTC timestamps, and Jalali/Tehran display timestamps for membership, last login and last activity.

## OTP/SMS requirements

- Password-reset OTP is 6 digits, one-time and short-lived.
- The database stores only an HMAC-SHA256 verifier protected with a server-only OTP pepper, never the raw OTP.
- Expiry, resend cooldown, maximum attempts, per-mobile hourly rate limit, per-IP hourly rate limit and replay prevention are enforced server-side.
- Public reset-request responses do not reveal whether the mobile number is registered.
- Production refuses the console/test SMS providers. A replaceable HTTPS webhook adapter is the production interface until the final Iranian SMS vendor is selected.
- Security-relevant events are recorded in the backend audit log.

## Build configuration

Flutter receives only the public API base URL at build time:

`--dart-define=DPA_API_BASE_URL=https://api.example.com`

Never put database credentials, JWT secrets, OTP pepper, SMS tokens or owner/admin passwords inside the APK.

A build without `DPA_API_BASE_URL` remains usable for offline peak browsing; account network actions intentionally report that the backend is not configured.
