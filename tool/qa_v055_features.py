#!/usr/bin/env python3
"""Static regression gate for DPA v0.5.5 input/completeness/autocomplete features."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def require(haystack: str, needle: str, label: str) -> None:
    if needle not in haystack:
        raise SystemExit(f'DPA v0.5.5 FEATURE QA FAILED: {label}')


pubspec = text('pubspec.yaml')
app_info = text('lib/app_info.dart')
normalizer = text('lib/utils/persian_normalizer.dart')
formatters = text('lib/utils/persian_input_formatters.dart')
repo = text('lib/data/peak_repository.dart')
owner = text('lib/pages/owner_edit_page.dart')
route = text('lib/pages/route_edit_page.dart')
stats = text('lib/pages/stats_page.dart')
importer = text('tool/import_excel.py')

require(pubspec, 'version: 0.5.7+15', 'app version is not 0.5.7+15')
require(app_info, "expectedSchemaVersion = '6'", 'runtime schema target is not 6')
for needle in (".replaceAll('ي', 'ی')", ".replaceAll('ك', 'ک')", 'normalizeNumberInput'):
    require(normalizer, needle, f'Persian normalizer missing {needle}')
require(formatters, 'class PersianTextInputFormatter', 'live Persian text formatter missing')
require(formatters, 'class LocalizedNumberInputFormatter', 'live localized-number formatter missing')
for needle in ('CREATE TABLE IF NOT EXISTS mountain_ranges', 'mountain_range_id', '_syncMountainRangeMaster', 'mountainRangeNames'):
    require(repo, needle, f'mountain-range master feature missing {needle}')
require(owner, 'RawAutocomplete<String>', 'mountain-range autocomplete missing')
require(owner, 'PersianTextInputFormatter', 'peak live Persian normalization missing')
require(route, 'LocalizedNumberInputFormatter', 'route live number normalization missing')
for needle in ("'$total - $safeCompleted = $missing'", 'const ColoredBox(color: Colors.red)', 'const ColoredBox(color: Colors.green)'):
    require(stats, needle, f'completed/missing stats UI missing {needle}')
if '1999 -' in stats or 'total = 1999' in stats:
    raise SystemExit('DPA v0.5.5 FEATURE QA FAILED: stats denominator must be dynamic, not hard-coded')
for needle in ("'ي': 'ی'", "'ك': 'ک'", 'normalize_digits'):
    require(importer, needle, f'Excel importer normalization missing {needle}')

print('DPA v0.5.5 FEATURE QA PASSED')
print('  completeness: green completed + red missing + dynamic subtraction')
print('  input: live Persian/Arabic and localized-number normalization')
print('  mountain ranges: persistent Schema 6 master + autocomplete/learning')
print('  import/search/save: shared canonical normalization paths present')
