# DPA v0.3.0 Backend/Auth Contract

DPA keeps peaks/routes offline in SQLite, but identity, password recovery, roles and authoritative user activity live on a central backend.

## Identity and roles

- Username is the normalized mobile number (Iranian numbers are sent as E.164, e.g. `+989121234567`).
- Roles: `user`, `admin`, `owner`.
- Server authorization is mandatory. UI hiding is not an authorization boundary.
- Passwords must never be stored or logged in plaintext. The backend must store a modern salted password hash (Argon2id preferred; bcrypt acceptable when configured appropriately).
- Access/refresh tokens are returned only after successful authentication. The Android app stores tokens only in OS secure storage.

## Endpoints used by the app

- `POST /v1/auth/register` — `display_name`, `mobile`, `username`, `password`
- `POST /v1/auth/login` — `mobile`, `username`, `password`
- `POST /v1/auth/logout` — bearer token
- `POST /v1/auth/change-password` — bearer token, current/new password
- `POST /v1/auth/password-reset/request` — `mobile`, `resend`; response includes `expires_in_seconds`, `resend_after_seconds`
- `POST /v1/auth/password-reset/confirm` — `mobile`, `code`, `new_password`
- `GET /v1/admin/users?limit=200&sort=newest|last_activity` — admin/owner only

Successful login/register response should contain `access_token`, optional `refresh_token`, and `user` with:
`user_id`, `display_name`, `mobile`, `email`, `status`, `role`, membership timestamps, last-login timestamps and last-activity timestamps.

## OTP/SMS requirements

- OTP is one-time, short-lived and stored server-side only as a protected verifier/hash.
- Enforce expiry, resend cooldown, maximum attempts, per-mobile/IP rate limits and replay prevention.
- Do not reveal whether an unknown mobile is registered in public reset responses.
- SMS delivery is behind a provider interface so the Iranian SMS provider can be replaced without changing the mobile app API.
- Audit admin/owner actions and security-relevant account events on the server.

## Build configuration

The app receives the backend URL at build time:

`--dart-define=DPA_API_BASE_URL=https://api.example.com`

A build without this value remains usable offline for peak browsing, but account network actions intentionally report that the backend is not configured.
