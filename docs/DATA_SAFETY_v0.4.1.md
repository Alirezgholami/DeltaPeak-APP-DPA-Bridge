# DPA v0.4.1 Data Safety

## Local peak/route data

DPA keeps the stable writable database name `dpa_peaks.db`. Existing data-safety rules from v0.3.0 remain: pre-migration safety snapshots, transactional migrations, integrity checks, validated ZIP restore, merge/replace-by-primary-key import, private GPX storage and SHA-256 duplicate protection. Unknown geographic/source values remain explicitly flagged instead of guessed.

## Authentication separation

The central backend is authoritative for identity, role, account status and activity timestamps. The app's local `users` table is non-secret profile/cache data only. Passwords and OTP values never enter app SQLite. Access and refresh tokens live only in Android secure storage and are excluded from backup/export.

Backend password hashes use Argon2id. OTP records contain an HMAC verifier, expiry, cooldown and attempt counters, not the raw SMS code. Refresh tokens are stored on the server as SHA-256 hashes. Password changes/resets invalidate previous access-token generations and revoke old refresh sessions.

## Production secrets

`DPA_JWT_SECRET`, `DPA_OTP_PEPPER`, SMS provider credentials, database credentials and owner/admin bootstrap credentials are server-only secrets. They must be supplied by the deployment secret manager/environment and must never be committed or compiled into the APK.

Production startup deliberately fails when JWT/OTP secrets are weak or when a console/test SMS provider is configured.


## v0.4.1 session behavior

Transient network failures during background refresh do not delete the cached offline session. Terminal refresh errors (invalid refresh token or inactive account) clear Secure Storage. Session profile revalidation and activity heartbeat contain no password, OTP, JWT secret, SMS credential, or database credential.
