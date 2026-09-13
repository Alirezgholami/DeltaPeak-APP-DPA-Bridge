# DPA v0.5.0 Data Safety

## Device

- Peak/route reference database remains offline-first in app SQLite.
- Authentication tokens are stored only through `flutter_secure_storage`.
- App database backups/exports explicitly exclude authentication secrets.
- Release client refuses a non-HTTPS `DPA_API_BASE_URL`.

## Backend

- Password hashes: Argon2id.
- OTP values: HMAC-SHA256 with a server-side independent pepper; raw OTP is not persisted.
- Refresh tokens: raw token returned only to client; SHA-256 hash stored server-side.
- Access-token revocation and account `auth_version` support logout and global session invalidation after password changes.
- Login brute-force controls: failed-attempt windows by mobile and source IP.
- Signup requires possession of the mobile number through OTP.
- Password-reset requests for unknown accounts still participate in cooldown/rate limiting.
- Audit log records security-sensitive events; heartbeat activity intentionally avoids audit-log spam.

## Production infrastructure

- PostgreSQL is not exposed publicly.
- FastAPI port 8080 is not published on the host in production Compose.
- Caddy is the only public HTTP/TLS entry point.
- API container runs as UID 10001, read-only filesystem, `no-new-privileges`, all Linux capabilities dropped.
- Real secrets are stored only in `.env.production`/server secret storage and excluded from Git/source snapshots.
- Database backups are excluded from Git and receive SHA-256 sidecars.
- Production Android distribution uses a dedicated release keystore; internal builds are explicitly marked debug-key-only.
