# DPA v0.5.0 Backend/Auth Contract

Base URL is injected into Flutter at build time with `DPA_API_BASE_URL`. Release builds accept HTTPS only.

## Public health

- `GET /health` — process/service health.
- `GET /ready` — database readiness.

## Verified sign-up

1. `POST /v1/auth/register/request`

```json
{"mobile":"09123456789","resend":false}
```

Returns `expires_in_seconds` and `resend_after_seconds`. Server applies OTP cooldown and hourly mobile/IP limits.

2. `POST /v1/auth/register/confirm`

```json
{
  "display_name":"Ali",
  "mobile":"09123456789",
  "code":"123456",
  "password":"strong-password"
}
```

Only a valid unconsumed signup OTP can create the account. Successful confirmation returns access token, rotating refresh token and user profile.

The legacy `POST /v1/auth/register` endpoint remains available only outside production for pre-v0.5 development compatibility. Production returns `signup_otp_required`.

## Login/session

- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `GET /v1/auth/me`
- `POST /v1/auth/activity`

Failed login attempts are rate-limited per mobile and per source IP. Unknown accounts still perform Argon2 verification against a dummy hash to reduce timing differences.

Refresh tokens are opaque, stored hashed server-side, single-use/rotating and revocable. Access tokens include an `auth_version`; password change/reset increments this version so older sessions are superseded.

## Password

- `POST /v1/auth/change-password` — authenticated password change.
- `POST /v1/auth/password-reset/request` — generic public response, OTP cooldown/rate limits.
- `POST /v1/auth/password-reset/confirm` — validates latest active reset OTP, remaining attempts and expiry.

Unknown reset targets still consume cooldown/rate-limit state but do not receive an SMS.

## Admin/Owner

- `GET /v1/admin/users?sort=newest&limit=100`
- `GET /v1/admin/users?sort=last_activity&limit=100`

Server authorizes only `admin` and `owner`; the Flutter UI visibility is not the security boundary.

## SMS provider contract

Supported providers:

- `console` — development only.
- `memory` — tests only.
- `webhook` — production HTTPS adapter.
- `kavenegar` — direct VerifyLookup adapter.

Two OTP purposes are supported: `signup` and `password_reset`, with separate template settings where available.
