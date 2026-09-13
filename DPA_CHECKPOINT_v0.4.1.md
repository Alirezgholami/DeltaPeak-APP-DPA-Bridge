# DPA v0.4.1 checkpoint

Reference: `DPA_SOURCE_v0.4.1.tar.gz` / Flutter `0.4.1+7`.

## Added in this increment
- Session reconciliation endpoint `GET /v1/auth/me`.
- Explicit activity heartbeat `POST /v1/auth/activity`; Flutter revalidates on startup/resume and sends a foreground heartbeat every 5 minutes so Owner/Admin last activity remains meaningful even though peak browsing is offline-first.
- SessionStore is observable so server-side role/profile/session changes refresh the UI.
- Deployment readiness endpoint `GET /ready` checks DB connectivity.
- Direct Kavenegar VerifyLookup SMS provider in addition to the generic webhook provider.
- Production config validation for Kavenegar/webhook secrets.
- Backend tests cover readiness, profile sync, activity heartbeat, and Kavenegar request shape.

## Still external / not embedded in source
- A real public HTTPS API hostname/server.
- PostgreSQL credentials and production secrets.
- Kavenegar API key + approved VerifyLookup template, or an equivalent webhook SMS adapter.
- GitHub secret `DPA_API_BASE_URL` pointing to the deployed backend.

No backend secret belongs in the Flutter APK.
- Production Docker hardening: no `change-me` database password, required secrets, PostgreSQL/API health checks, trusted-proxy allowlist, and `scripts/generate_secrets.py`.
