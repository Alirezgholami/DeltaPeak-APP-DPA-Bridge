# DPA v0.1.0 — Data/Code Audit

Audit performed against the uploaded handoff and the bundled reference workbook.

## Verified source files

- App handoff commit: `19f3d90dfd219aa61689979f79da23a08b4269b2`
- App version in handoff: `0.1.0+1`
- Bundled app database: `assets/peaks.db`
- Reference workbook supplied with handoff:
  `DeltaPeakDatabase_V3_88_PublicResearch_AmbiguityAudit_Batch05.xlsx`
- Reference workbook SHA-256:
  `5381f92d2d1879ee41e2a08cc8025c2ff912483bc90f031d5a743f890b2a4227`

## Root causes of incomplete v0.1.0

1. The UI and README were hard-coded to **DPD V3.82**, not V3.88.
2. The local database filename was hard-coded as `dpa_peaks_v382.db`.
3. The SQLite schema omitted important V3.88 fields, including:
   - trailhead elevation
   - elevation gain / height difference
   - route length
   - ascent time
   - round-trip time
   - difficulty
   - best season
   - guide requirement
   - route status
   - number of routes
4. The bundled SQLite data was not byte/data-equivalent to the supplied V3.88 workbook. Across the fields common to both schemas, 106 cell values differ from the V3.88 reference.
5. The app displayed the number of loaded search results, not a full audited database statistics view.
6. There was no metadata table, source hash, schema version, or build-time database QA gate.

## What V3.88 itself actually contains

The reference workbook has **2000 registry records**. Some important fields are still incomplete in the source itself:

| Field | Filled | Percent |
|---|---:|---:|
| Summit elevation | 1820 | 91.0% |
| County | 321 | 16.1% |
| District | 641 | 32.0% |
| Summit coordinates | 1290 | 64.5% |
| Main route | 642 | 32.1% |
| Trailhead | 321 | 16.1% |
| Trailhead elevation | 102 | 5.1% |
| Elevation gain | 119 | 6.0% |
| Route length | 131 | 6.5% |
| Difficulty | 169 | 8.4% |
| Best season | 72 | 3.6% |
| Route status | 1089 | 54.5% |

Therefore v0.1.1 can correctly expose all existing V3.88 fields, but it cannot honestly claim those source fields are complete. Completing them requires a separate DPD enrichment pass using verified GPX/public evidence.

## v0.1.1 corrective controls

- DPD v3.88 source workbook included in the project.
- SQLite Schema v2 includes all registry fields required by the app.
- Metadata table stores database version, source filename, source SHA-256, schema version, record counts.
- Dynamic app/database version display.
- Database statistics and per-province counts.
- Data completeness indicators.
- Local Owner edit for all data fields with audit log.
- Versioned local database path to prevent stale v3.82 persistence.
- GitHub Actions rebuilds the SQLite database from the audited V3.88 workbook before APK build.
- QA gate blocks the build when version/schema/record count/core completeness checks fail.
- Member-sensitive data and protected GPX files are explicitly kept out of the offline APK database pending secure backend integration.

## v0.1.2 province-label cleanup

The audited workbook remains the immutable DPD v3.88 evidence source with 2000 registry rows. DPA v0.1.2 applies a mobile-data migration layer: 24 legacy shared-province labels are resolved to one official province and the one explicitly non-canonical combined Yurd source record is excluded because Yurd Haji and Yurd Sharif already exist as separate peaks. The app database therefore contains 1999 rows and exactly 31 official province labels.
