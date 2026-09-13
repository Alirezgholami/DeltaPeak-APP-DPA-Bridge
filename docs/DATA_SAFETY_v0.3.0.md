# DPA v0.3.0 Data Safety

## Database migration

The writable app database has the stable filename `dpa_peaks.db`. Existing known v0.2 database files are copied to the stable path; they are not deleted. Before a schema upgrade DPA creates a pre-migration snapshot in the app-private `safety_snapshots` directory. Schema changes are applied in a transaction and followed by SQLite integrity checks.

No future release is allowed to solve `database_version`/`schema_version` changes by deleting the user's writable database. `tool/qa_data_safety.py` is a CI gate for this invariant.

## Backup / Restore / Import / Export

- Backup is a versioned ZIP package with `manifest.json`, `data.json`, and eligible GPX files.
- Restore validates format/schema and rejects unsafe ZIP paths.
- A safety backup is created immediately before restore.
- JSON Import uses merge/replace-by-primary-key semantics; it does not drop the database.
- Admin/Owner may include reference peak/route/audit data and GPX files.
- Normal users back up favorites and non-sensitive settings only.

## Authentication data

Passwords and OTP values are never persisted in SQLite. Access/refresh tokens are never included in Backup/Export and live only in Android secure storage. The local `users` table is a non-secret profile/cache needed for offline foreign-key relationships; the backend remains authoritative.

## Data quality

Schema 4 adds `map_elevation`, `data_flags`, and `data_quality_status`. Missing summit coordinates, mountain range, map elevation, or summit-sign elevation are explicitly flagged. Ambiguous/unresolved source states are marked `needs_manual_review`; unknown values are not guessed.

## GPX files

Imported GPX files are copied into app-private storage and named by SHA-256. An existing active route with the same SHA-256 blocks duplicate import. Route-specific trailhead latitude/longitude are independent from summit coordinates.
