# DPA v0.3.0+5 Checkpoint

Scope: Accounts + Data Safety + Organic Maps + trailhead coordinates + data-quality flags.

Implemented app-side:
- Mobile-number username, Register/Login/Logout, Change Password, OTP Reset/Resend UI and backend contract.
- Secure token storage; no password/OTP/token in SQLite Backup/Export.
- `user/admin/owner` role model and admin/owner user list with newest/last-activity sorting.
- Theme: System / Light / Dark persisted in `app_settings`.
- Peak labels: `ارتفاع قله (تابلو)` and `ارتفاع قله (Map)`.
- Summit and route-trailhead Organic Maps links generated at runtime.
- Stable `dpa_peaks.db`, safety snapshot, Schema 4 migration, Backup/Restore/Import/Export.
- Favorites, search/filters, completeness/needs-review, Soft Delete + restore, per-peak Audit History.
- GPX private storage + SHA-256 duplicate protection.
- Future sync outbox and About/Database Info.

Bundled DB gate:
- DPD v3.88, Schema 4, 1999 publishable peaks, 876 route scaffolds, exactly 31 official provinces.
- Missing/ambiguous source data is flagged rather than invented.

External dependencies before production account flow:
- Deploy backend matching `docs/BACKEND_API_CONTRACT_v0.3.0.md`.
- Connect an SMS provider on the backend.
- Build with `DPA_API_BASE_URL`.

Data enrichment remains a DPD research task. The v0.3.0 importer now extracts only explicit, unambiguous evidence already present in DPD v3.88: 1290 summit coordinate pairs, 164 map-sourced elevation values, and 19 explicitly named mountain ranges. DPD v3.88 has no dedicated mountain-range column and currently provides no route trailhead coordinate pairs, so the remaining gaps stay empty and receive data-quality flags instead of guessed values.
