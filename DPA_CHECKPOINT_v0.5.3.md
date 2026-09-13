# DPA v0.5.3+11

## Reference data
- Bundled database: **DPD v3.90 + v3.91 enrichment B09**.
- Schema: **5**.
- Dataset revision: **v390-v391b09-safe-overlay-v1**.
- Publishable peaks: **1999**.
- Official province labels: **31**.
- GPX route records/scaffolds: **918**.
- V3.91 conflict/HOLD rows are intentionally not merged.

## Data improvements vs v0.5.2
- Summit coordinates: 1290 -> **1360**.
- Counties: 321 -> **334**.
- Districts: 640 -> **641**.
- Peak route text: 642 -> **682**.
- Trailheads: 321 -> **372**.
- Trailhead elevations: 102 -> **211**.
- Elevation gain: 119 -> **224**.
- Route length: 131 -> **234**.
- Mountain range: 19 -> **51**.
- Route trailhead coordinate pairs: 0 -> **1**.

## Phone-data safety
- Existing writable DB remains `dpa_peaks.db`.
- Upgrade from Schema 4 creates a pre-migration safety snapshot.
- Reference merge uses `REF-V390-B09` and fills only empty reference fields.
- Any peak field already present in local audit history is protected from reference overwrite.
- Any locally added/edited route is protected from reference overwrite.
- Favorites, local peaks, soft deletes, users, wallets, payments, orders, entitlements and imported GPX paths remain local and are not replaced.
- New reference routes are inserted only when their `route_id` does not already exist.

## Validation
- Database QA: PASS.
- Data-safety static QA: PASS.
- Backend tests: 5/5 PASS.
- Old-v0.5.2 -> new-reference merge simulation: PASS; protected edit, favorite, and local peak preserved.

## Provenance
- V3.90 master SHA-256: `20fb7302a16447fd5383a96d51e6fa5a118c20ae542c7d16b4e19e4ec54398a0`
- V3.91 B09 workbook SHA-256: `d3c0c7bfe136fc98d1977d6c9b5ad0cd1e85a17c88c5e43d99c86c06f07c7a67`
- B09 JSON SHA-256: `f1f6e31e59e1c4a3097b946ee03c0ca0779d06569f3fdcb258ad8ad6ba9e212f`
- Bundled peaks.db SHA-256: `df1d9659b8cf5678869732029a450626d48e7606a93961217cb5433024e32360`

Note: the full standalone V3.91 master workbook is not present in the currently accessible Library snapshot. This build therefore identifies itself accurately as **V3.90 + validated V3.91 B09 enrichment**, rather than falsely claiming a full V3.91 reimport.
