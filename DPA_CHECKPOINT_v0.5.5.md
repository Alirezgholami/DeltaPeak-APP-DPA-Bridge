# DPA v0.5.5+13 — Persian Normalization + Completeness + Mountain Range Master

## Reference state
- App: **DPA 0.5.5+13**
- Bundled reference database: **DPD v3.90 + v3.91 enrichment B10**
- Bundled DB schema: **5**
- Runtime schema target after non-destructive migration: **6**
- Dataset revision: **v390-v391b10-corefields-v2**
- Publishable peaks: **1999**
- Route records/scaffolds: **919**
- Province labels: **31 official provinces**

> This release changes app behavior/schema, not the bundled DPD content revision. DPD v3.92 is not claimed as bundled in this source package.

## Implemented in v0.5.5
1. **Completeness UI now shows both present and missing data.**
   - Denominator is dynamic `recordCount` (currently 1999 publishable peaks), never hard-coded.
   - Each row shows `completed / total` and a red `total - completed = missing` line.
   - Each progress bar is always 100% wide: green = completed, red = missing.
   - Placeholder values are excluded from text completeness; positive numeric fields require `> 0`.
   - Added name, province, route duration and GPX-route coverage rows.

2. **Persian normalization is centralized and applied during input/save/search/import.**
   - `ي/ى/ے → ی`, `ك → ک`, Arabic alef variants → `ا`, Arabic heh variants → `ه`.
   - Tatweel/Arabic diacritics removed; whitespace normalized; ZWNJ preserved.
   - Persian/Arabic digits and localized decimal separators normalized before numeric parsing.
   - Peak/route forms normalize live while typing, and repository save remains the defensive second layer.
   - Raw provenance text and URLs are intentionally not rewritten.

3. **Persistent mountain-range master + autocomplete.**
   - Runtime Schema 6 adds `mountain_ranges` and `peaks.mountain_range_id`.
   - Existing non-empty mountain ranges seed the master non-destructively on first migration.
   - Suggestions begin from the first typed character; prefix matches precede contains matches.
   - Usage count ranks frequently used ranges higher.
   - A genuinely new normalized name is learned on save and persists across app restarts.
   - Existing Arabic/Persian orthographic variants resolve to one normalized master record.
   - Existing `mountain_range` text remains for backward compatibility.

4. **Search compatibility after migration.**
   - Existing peak search keys are rebuilt through the new Persian normalizer so old Arabic spelling variants remain searchable without rewriting provenance/source fields.

5. **Regression protection.**
   - Added `tool/qa_v055_features.py` and wired it into both Android build workflows.
   - Added backend Persian-normalization tests.
   - Invalid optional numeric text is blocked by form validation instead of silently clearing a prior numeric value.

## Current completeness basis (bundled DPD v3.90+B10)
| Field | Completed | Missing of 1999 |
|---|---:|---:|
| Peak name | 1999 | 0 |
| Province | 1999 | 0 |
| Summit sign elevation (>0) | 1820 | 179 |
| Map elevation (>0) | 216 | 1783 |
| County | 335 | 1664 |
| District | 642 | 1357 |
| Summit coordinates | 1361 | 638 |
| Legacy main route | 684 | 1315 |
| Trailhead name | 374 | 1625 |
| Trailhead coordinate pair (route-linked peaks) | 105 | 1894 |
| Trailhead elevation (>0) | 212 | 1787 |
| Elevation gain (>0) | 230 | 1769 |
| Route length (>0) | 235 | 1764 |
| Route duration (route-linked peaks) | 142 | 1857 |
| Difficulty | 174 | 1825 |
| Best season | 73 | 1926 |
| Route status | 1088 | 911 |
| Mountain range | 59 | 1940 |
| Description | 1999 | 0 |
| GPX route record/scaffold (distinct peaks) | 919 | 1080 |

## Validation completed in this environment
- Python compile checks: **PASS**
- DPD bundled database QA: **PASS**
- Data Safety static QA: **PASS**
- v0.5.5 feature regression gate: **PASS**
- Backend tests: **7/7 PASS**
- Excel/import Persian normalization smoke: **PASS**
- Schema-6 mountain-range migration simulation: **PASS** — 19 master range names, 59 linked active peaks, 0 orphan IDs
- Dart source lexical bracket/brace balance: **PASS**
- Full `flutter analyze` / `flutter test`: **not runnable locally here because Flutter SDK is not installed**; both remain mandatory in GitHub Actions before APK output.

## Data-safety policy
- Writable phone DB stays at stable `dpa_peaks.db`.
- Upgrade is non-destructive and takes a pre-migration safety snapshot.
- User/Owner edits are not overwritten by reference-data fill-empty merges.
- New range master data is local DB data and is included in the normal runtime database lifecycle.
