# Delta Peak (DPA) v0.5.6

DPA is an offline-first Flutter mountain application backed by the DPD v3.90 master plus validated v3.91 B09 and B10 core-field enrichment overlays and a separate production account backend.

## Current reference

- Flutter app: `0.5.6+14`
- Backend: `0.5.0`
- DPD reference in this build: `v3.90 + v3.91 enrichment B10`
- Publishable peaks: `1999`
- GPX route scaffolds: `919`
- Provinces: exactly `31` official province labels

## Account features

- Sign up with Iranian mobile number as username.
- Mobile ownership verification by OTP before account creation.
- Sign in / sign out.
- Password change.
- Password recovery by OTP + resend controls.
- Access + rotating refresh sessions.
- Owner/Admin user list with latest login/activity.
- Accurate foreground activity heartbeat while peak data stays offline.

## Production security/deployment

- Argon2id passwords, HMAC-protected OTP records, hashed refresh tokens.
- Per-mobile/IP OTP and login abuse limits.
- Release app accepts HTTPS Backend only.
- PostgreSQL + Alembic + FastAPI.
- Caddy reverse proxy with automatic HTTPS.
- Hardened non-root API container.
- Internal and production-signed Android build workflows are separated.

## v0.5.1 internal-owner/UI update

- Internal APKs expose Add / Edit / Soft Delete / Restore locally without requiring the production account backend.
- Production builds still require an authenticated Owner/Admin for reference-data management.
- Favorites text filter moved to Settings; Home now has a compact heart-only shortcut beside the province selector.

Start with:

- `DPA_CHECKPOINT_v0.5.1.md`
- `docs/BACKEND_API_CONTRACT_v0.5.0.md`
- `docs/DATA_SAFETY_v0.5.0.md`
- `backend/DEPLOY_PRODUCTION.md`

The next live step requires real infrastructure inputs: API domain, VPS, SMS credentials/templates and Android release-signing key.


## v0.5.2 home filter cleanup
- Removed the horizontal filter-chip row from Home.
- Moved Coordinates / GPX / data-quality filters into Settings.
- Kept only the compact favorite-heart control next to the province selector.
- Home reloads persisted filter settings after returning from Settings.


## v0.5.5 Persian input + completeness UX

- Completeness bars now always span 100%: completed is green, missing is red, with `total - completed = missing`.
- Persian/Arabic input is normalized live while typing and again before persistence/search; localized digits are normalized live and before numeric parsing.
- `mountain_ranges` is a persistent master table (runtime Schema 6) with usage counts and canonical normalized names.
- Peak editor suggests mountain ranges from the first typed character; new names are learned on save.
- Import/restore and route editing use the same normalization layer.

## v0.5.4 core-field reference-data migration
- V3.90 is imported with its explicit `description`, `mountain_range`, `map_elevation`, GPX elevation-gain and trailhead-coordinate fields instead of silently dropping them.
- Validated V3.91 B09 is applied first; B10 then adds high-confidence core-field evidence for At Daghi, Ainakhli and Til Daghi.
- B10 adds one Ainakhli route as draft metadata and keeps the Ayqar province/name conflict on HOLD.
- Bundled reference DB now contains 1999 peak descriptions, 216 Map elevations, 1361 summit-coordinate pairs, 59 mountain-range values and 105 route trailhead-coordinate pairs.
- Existing phone data remains protected by fill-empty-only reference merge and audit-protected local edits.
- Existing local peaks, favorites, soft-delete state, purchases, users, wallet/payment data and imported GPX files are not replaced by the reference merge.


## v0.5.6 education completion

- Education remains organized in the agreed 6 categories but expands from 6 placeholders to 42 published lessons.
- Navigation/GPX is the deepest section: GPX, Track/Route/Waypoint, offline maps, AlpineQuest import/record/export workflow, GPS error, elevation/distance concepts and DPA multi-route guidance.
- Category pages now show searchable lesson lists instead of expanding every long article at once.
- Article pages support selectable RTL text and clickable external links.
- A one-time `EDU-V1-20260912` data migration upgrades existing installations non-destructively: only the six legacy placeholder article IDs are removed; unknown/custom education rows are preserved.
- Fresh installs and upgrades use the same `assets/education_v1.json` canonical content pack.
