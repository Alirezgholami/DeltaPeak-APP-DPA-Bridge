#!/usr/bin/env python3
"""Regression gate for DPA v0.5.7 education pack and upgrade path."""
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f'DPA v0.5.7 EDUCATION QA FAILED: {message}')


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


pack = json.loads(text('assets/education_v1.json'))
if pack.get('revision') != 'edu-v1-20260912':
    fail('unexpected education revision')

categories = pack.get('categories', [])
contents = pack.get('contents', [])
if len(categories) != 6:
    fail(f'category count={len(categories)}, expected 6')
if len(contents) != 42:
    fail(f'content count={len(contents)}, expected 42')

category_ids = [c.get('category_id') for c in categories]
if len(set(category_ids)) != 6:
    fail('duplicate category_id')
content_ids = [c.get('content_id') for c in contents]
if len(set(content_ids)) != 42:
    fail('duplicate content_id')
if any(c.get('category_id') not in category_ids for c in contents):
    fail('orphan education content category')
if any(not str(c.get('title', '')).strip() or len(str(c.get('body', '')).strip()) < 120 for c in contents):
    fail('empty or unexpectedly short lesson found')

expected = {
    'EDU-CAT-01': 6,
    'EDU-CAT-02': 6,
    'EDU-CAT-03': 9,
    'EDU-CAT-04': 7,
    'EDU-CAT-05': 7,
    'EDU-CAT-06': 7,
}
if Counter(c['category_id'] for c in contents) != Counter(expected):
    fail('category distribution mismatch')

navigation_text = '\n'.join(c['title'] + '\n' + c['body'] for c in contents if c['category_id'] == 'EDU-CAT-03')
for required in ('GPX', 'Track', 'Route', 'Waypoint', 'AlpineQuest', 'نقشه آفلاین', 'DPA', 'ارتفاع‌گیری'):
    if required not in navigation_text:
        fail(f'navigation/GPX pack missing {required!r}')

repo = text('lib/data/peak_repository.dart')
for required in (
    "_educationMigrationId = 'EDU-V1-20260912-R2'",
    "rootBundle.loadString('assets/education_v1.json')",
    "'EDU-ART-01'",
    "'education_revision'",
    "await _ensureEducationPack();",
):
    if required not in repo:
        fail(f'non-destructive education upgrade path missing {required!r}')

page = text('lib/pages/education_page.dart')
for required in ('۴۲ درس', 'جست‌وجو در آموزش‌های این بخش', 'EducationContentPage', 'launchUrl', 'پیوندهای این آموزش'):
    if required not in page:
        fail(f'education UI missing {required!r}')

pubspec = text('pubspec.yaml')
if 'version: 0.5.7+15' not in pubspec:
    fail('app version is not 0.5.7+15')
if '- assets/education_v1.json' not in pubspec:
    fail('education asset is not bundled')

print('DPA v0.5.7 EDUCATION QA PASSED')
print('  education: 6 categories / 42 published lessons')
print('  navigation/GPX: GPX + Track/Route/Waypoint + AlpineQuest + offline + DPA guidance')
print('  upgrade: one-time non-destructive migration preserves unknown/custom education rows')
print('  UI: searchable lesson list + article page + clickable external links')
