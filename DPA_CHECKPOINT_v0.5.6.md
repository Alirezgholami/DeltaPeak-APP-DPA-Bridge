# DPA v0.5.6+14 — Education Completion

Date: 2026-09-12

## Reference state
- App: **DPA 0.5.6+14**
- Bundled reference database: **DPD v3.90 + v3.91 enrichment B10**
- Bundled DB schema: **5**
- Runtime schema target: **6**
- Dataset revision: **v390-v391b10-corefields-v2**
- Publishable peaks: **1999**
- GPX route records/scaffolds: **919**
- Province labels: **31 official provinces**

## Education completion
The agreed six-category structure is retained:
1. کوهنوردی مقدماتی — 6 lessons
2. تجهیزات — 6 lessons
3. مسیریابی و GPX — 9 lessons
4. ایمنی — 7 lessons
5. هواشناسی — 7 lessons
6. کمک‌های اولیه — 7 lessons

Total: **42 published lessons**.

The Navigation/GPX section includes GPX concepts, Track/Route/Waypoint, pre-hike track review, offline maps, AlpineQuest GPX workflow, AlpineQuest offline-map/track-recorder workflow, GPS error, route length/elevation-gain concepts, and DPA multi-route usage.

The user-provided AlpineQuest training direction is incorporated and extended. The pack includes the user-provided Bale training channel link plus AlpineQuest official help.

## Upgrade safety
- Canonical content asset: `assets/education_v1.json`
- Education revision: `edu-v1-20260912`
- Data migration marker: `EDU-V1-20260912`
- Existing installs receive the pack at runtime without replacing the writable phone database.
- Only legacy placeholder IDs `EDU-ART-01` ... `EDU-ART-06` are removed.
- Unknown/custom education rows are preserved.
- Fresh DB builds and runtime upgrades consume the same content pack.

## UI
- Education landing page shows the six categories with descriptions and icons.
- Category pages show searchable article lists with previews.
- Search uses the shared Persian normalizer.
- Article pages are RTL/selectable and expose detected HTTP/HTTPS links as tappable buttons.

## Validation
- Bundled DB QA: PASS — 1999 peaks / 919 routes / 31 provinces / 6 categories / 42 lessons.
- Data Safety QA: PASS.
- v0.5.5 feature-regression gate: PASS.
- v0.5.6 education gate: PASS.
- Python compile: PASS.
- Backend tests: 7/7 PASS.
- v0.5.5 -> v0.5.6 education migration simulation: PASS; custom education row preserved; legacy placeholders removed; foreign keys/integrity PASS.
- Dart lexical balance smoke check: PASS.
- Full Flutter analyze/test cannot run in this container because Flutter/Dart SDK is not installed; both remain mandatory in GitHub Actions before APK output.
