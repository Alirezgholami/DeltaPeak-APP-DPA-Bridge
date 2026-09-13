# DPA CHECKPOINT — v0.5.0+8

Reference snapshot: `DPA_SOURCE_v0.5.0.tar.gz`

## Completed in this release

- Secure two-step mobile signup with OTP verification.
- Separate signup/reset OTP purposes and SMS templates.
- Kavenegar VerifyLookup adapter supports separate signup/reset templates.
- Login brute-force rate limiting by mobile and IP.
- Constant-cost dummy Argon2 verification for unknown login users.
- Unknown password-reset targets now consume OTP cooldown/rate-limit state.
- Release Flutter client rejects non-HTTPS Backend URL.
- Generic production VPS deployment with PostgreSQL + FastAPI + Caddy automatic TLS.
- API is not host-exposed; PostgreSQL is on an internal network.
- API Docker hardening: unprivileged user, read-only root FS, dropped capabilities, no-new-privileges.
- Production environment initializer and preflight validator.
- PostgreSQL backup script + SHA-256 checksum.
- HTTPS smoke-test script.
- Separate Internal APK and Production Signed APK GitHub workflows.
- Production Android signing support via JKS/key.properties.
- Current GitHub Actions generations: checkout v6 and upload-artifact v7.
- APK proof text corrected to report current app/schema dynamically instead of stale v0.2.0 text.

## Quality gates executed in this workspace

- Backend pytest: 5 passed.
- DPD v3.88 SQLite QA: PASS.
- Data Safety static QA: PASS.
- Production env generator + preflight self-test: PASS.
- Docker Compose / GitHub workflow YAML parse: PASS.
- Database remains: 1999 publishable peaks, 876 GPX route scaffolds, exactly 31 official province labels.

## External inputs still required for a live production system

1. VPS public IP / SSH access.
2. Real API domain/subdomain with DNS pointed to the VPS.
3. SMS provider credentials and approved OTP templates.
4. Android production release keystore + GitHub signing secrets.

No real server, domain, SMS credential or signing private key is embedded in this snapshot.
