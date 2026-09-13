# DPA v0.5.4+12 — Core Fields Completion B10

## Reference state
- Database: **DPD v3.90 + v3.91 enrichment B10**
- Schema: **5**
- Dataset revision: **v390-v391b10-corefields-v2**
- Publishable peaks: **1999**
- Route records/scaffolds: **919**
- Province labels: **31 official provinces**

## Core-field completeness after importer repair + B09 + B10
| Field | Filled | Missing |
|---|---:|---:|
| Summit sign elevation | 1820 | 179 |
| Map elevation | 216 | 1783 |
| County | 335 | 1664 |
| District | 642 | 1357 |
| Summit coordinates | 1361 | 638 |
| Main route text | 684 | 1315 |
| Trailhead name | 374 | 1625 |
| Trailhead elevation | 212 | 1787 |
| Elevation gain | 231 | 1768 |
| Route length | 235 | 1764 |
| Ascent time | 121 | 1878 |
| Round-trip time | 125 | 1874 |
| Difficulty | 174 | 1825 |
| Best season | 73 | 1926 |
| Route status | 1088 | 911 |
| Mountain range | 59 | 1940 |
| Description | 1999 | 0 |
| Route trailhead coordinate pairs | 105 | — |

## What changed
1. Fixed the V3.90 importer so explicit descriptions, map elevations, mountain ranges, GPX elevation gain and trailhead coordinates are no longer discarded.
2. Applied B09 fill-empty-only enrichment.
3. Applied B10 high-confidence core-field updates:
   - **آت داغی**: Summit coordinates + Map elevation 2992m; sign 3002m preserved.
   - **آیناخلی**: county/district + route/trailhead/start elevation/gain/length/time/difficulty + draft route metadata.
   - **تیل داغی**: Misho range + Til-village route/trailhead.
   - **آیقار**: conflicting cross-province/same-name evidence held for manual review; not merged.
4. Reference merge remains non-destructive for phone/user data.

## Validation
- Database QA: PASS
- Data safety QA: PASS
- Backend tests: 5/5 PASS

## Source hashes
- V3.90 master: `20fb7302a16447fd5383a96d51e6fa5a118c20ae542c7d16b4e19e4ec54398a0`
- B09 workbook: `d3c0c7bfe136fc98d1977d6c9b5ad0cd1e85a17c88c5e43d99c86c06f07c7a67`
- B10 workbook: `051db7caa07524576dffd254419aae904a04baf268757649d1ded595a2db37d7`
- B09 JSON: `f1f6e31e59e1c4a3097b946ee03c0ca0779d06569f3fdcb258ad8ad6ba9e212f`
- B10 JSON: `eaa3c16a01476984646b84a37ff6db27976b9a00ea35a359ad84a2878ca2552b`
- peaks.db: `84ec93dbb9fccd453cac08d96c21f95eb557067c72b89c8cde98214963384937`
