#!/usr/bin/env python3
"""Static safety gate for DPA database/auth/backup invariants."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
repo = (ROOT / 'lib/data/peak_repository.dart').read_text(encoding='utf-8')
backup = (ROOT / 'lib/services/backup_service.dart').read_text(encoding='utf-8')
session = (ROOT / 'lib/auth/session_store.dart').read_text(encoding='utf-8')
auth = (ROOT / 'lib/auth/auth_service.dart').read_text(encoding='utf-8')


def fail(msg: str):
    raise SystemExit(f'DPA DATA SAFETY QA FAILED: {msg}')


if "p.join(docs.path, 'dpa_peaks.db')" not in repo:
    fail('stable writable database path dpa_peaks.db is missing')

for pattern in (r'deleteDatabase\s*\(', r'File\s*\(\s*_dbPath\s*\)\.delete\s*\('):
    if re.search(pattern, repo):
        fail(f'destructive writable-database deletion pattern found: {pattern}')

if '_createPreMigrationSnapshotIfNeeded' not in repo or '_migrateSchema' not in repo:
    fail('non-destructive migration/snapshot path missing')

if '_mergeBundledReferenceDataIfNeeded' not in repo or "CREATE TABLE IF NOT EXISTS data_migrations" not in repo:
    fail('safe reference-data merge path or data_migrations marker table missing')

if "_isEmptyReferenceValue(localValue)" not in repo or 'protectedPeakFields' not in repo or 'protectedRouteIds' not in repo:
    fail('reference merge is not guarded by fill-empty and local-edit protection')

if "'contains_authentication': false" not in backup:
    fail('backup manifest does not explicitly exclude authentication')

if "key.contains('token')" not in repo or "key.contains('password')" not in repo or "key.contains('otp')" not in repo:
    fail('safe export does not filter token/password/otp settings')

if 'flutter_secure_storage' not in (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'):
    fail('secure storage dependency missing')

if 'FlutterSecureStorage' not in session:
    fail('session tokens are not stored through secure storage')

for forbidden in ('CREATE TABLE auth', 'password_hash', 'plain_password'):
    if forbidden.lower() in repo.lower():
        fail(f'authentication secret storage found in local database code: {forbidden}')

if "String.fromEnvironment(\n    'DPA_API_BASE_URL'" not in auth:
    fail('backend URL is not build-time configurable')

if "username': normalized" not in auth or "mobile': normalized" not in auth:
    fail('mobile-as-username login contract missing')

if 'kReleaseMode && !isHttpsConfigured' not in auth:
    fail('release client does not enforce HTTPS backend URL')

if "/v1/auth/register/request" not in auth or "/v1/auth/register/confirm" not in auth:
    fail('verified-mobile signup contract missing')

print('DPA DATA SAFETY QA PASSED')
print('  writable DB: stable dpa_peaks.db')
print('  migrations: safety snapshot + non-destructive schema/reference-data migration')
print('  auth secrets: excluded from SQLite backup/export; tokens in secure storage')
print('  backend auth: build-time DPA_API_BASE_URL + HTTPS release guard + OTP signup')
