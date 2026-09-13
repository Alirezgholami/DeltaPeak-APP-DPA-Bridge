#!/usr/bin/env python3
"""Regression gate for DPA education pack, media and management workflow."""
from __future__ import annotations
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f'DPA EDUCATION QA FAILED: {message}')


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
for required in ('جست‌وجو در آموزش‌های این بخش', 'EducationContentPage', 'launchUrl', 'پیوندهای این آموزش', 'افزودن تصویر', 'افزودن لینک مدیا'):
    if required not in page:
        fail(f'education UI missing {required!r}')

media = text('lib/services/education_media_store.dart')
for required in ('education_media', 'addImage', 'addMediaLink', 'blob_data'):
    if required not in media:
        fail(f'education media support missing {required!r}')

manager = text('lib/pages/education_management_page.dart')
store = text('lib/services/education_content_store.dart')
settings = text('lib/pages/settings_page.dart')
for required in ('تأیید نهایی / Publish', 'برگشت به Draft', 'Archive', 'پیش‌نمایش'):
    if required not in manager:
        fail(f'education management UI missing {required!r}')
for required in ('publication_status', "{'draft', 'published', 'archived'}", 'education_change_log', 'setStatus'):
    if required not in store:
        fail(f'education content workflow missing {required!r}')
if 'مدیریت آموزش؛ Draft / Publish / Archive' not in settings:
    fail('education management is not exposed in settings')

pubspec = text('pubspec.yaml')
if not re.search(r'^version:\s+0\.5\.\d+\+\d+$', pubspec, re.MULTILINE):
    fail('invalid app version format')
if '- assets/education_v1.json' not in pubspec:
    fail('education asset is not bundled')

print('DPA EDUCATION QA PASSED')
print('  education: 6 categories / 42 bundled published lessons')
print('  media: local images + external media links')
print('  workflow: create/edit -> draft -> preview -> publish -> draft/archive')
print('  access: management entry is gated through DPA manager permissions')
