#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, re, sqlite3, tempfile, zipfile
from pathlib import Path
from qa_database import main as qa_database

ROOT = Path(__file__).resolve().parents[1]
DB_MEMBER = 'assets/flutter_assets/assets/peaks.db'


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def app_version() -> str:
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*(\S+)', text, flags=re.M)
    return m.group(1) if m else 'unknown'


def main(apk_path: Path, proof_path: Path, api_base_url: str = ''):
    if not apk_path.exists():
        raise SystemExit(f'APK VERIFY FAILED: APK not found: {apk_path}')
    with zipfile.ZipFile(apk_path) as zf:
        if DB_MEMBER not in set(zf.namelist()):
            raise SystemExit(f'APK VERIFY FAILED: {DB_MEMBER} not found')
        with tempfile.TemporaryDirectory() as td:
            extracted = Path(td) / 'apk_peaks.db'
            extracted.write_bytes(zf.read(DB_MEMBER))
            qa_database(str(extracted))
            db = sqlite3.connect(extracted)
            try:
                meta = dict(db.execute('SELECT key,value FROM metadata'))
                route_count = db.execute('SELECT COUNT(*) FROM gpx_routes').fetchone()[0]
                edu_cats = db.execute('SELECT COUNT(*) FROM education_categories').fetchone()[0]
                edu_items = db.execute('SELECT COUNT(*) FROM education_contents').fetchone()[0]
                completeness = {}
                for field in ('elevation','county','district','latitude','route','trailhead','trailhead_elevation_m','elevation_gain_m','route_length_km','mountain_range','description'):
                    completeness[field] = db.execute(
                        f"SELECT COUNT(*) FROM peaks WHERE is_deleted=0 AND {field} IS NOT NULL AND TRIM(CAST({field} AS TEXT))<>''"
                    ).fetchone()[0]
            finally:
                db.close()

            lines = [
                'DPA BUILD PROOF', '===============',
                f'APP_VERSION: {app_version()}',
                f'APK: {apk_path.name}', f'APK_SHA256: {sha256(apk_path)}',
                f'APP_DATABASE_MEMBER: {DB_MEMBER}', f'APP_DATABASE_SHA256: {sha256(extracted)}',
                f'DATABASE_VERSION: {meta.get("database_version")}', f'SCHEMA_VERSION: {meta.get("schema_version")}',
                f'DATASET_REVISION: {meta.get("dataset_revision")}', f'SOURCE_RECORD_COUNT: {meta.get("source_record_count")}',
                f'RECORD_COUNT: {meta.get("record_count")}', f'CONTROLLED_EXCLUSIONS: {meta.get("controlled_exclusion_count")}',
                f'GPX_ROUTE_SCAFFOLDS: {route_count}', f'EDUCATION_CATEGORIES: {edu_cats}', f'EDUCATION_CONTENTS: {edu_items}',
                f'SOURCE_FILE: {meta.get("database_source_file")}', f'SOURCE_SHA256: {meta.get("database_source_sha256")}',
                f'GENERATED_AT_JALALI: {meta.get("generated_at_jalali")}',
            ]
            if api_base_url:
                lines.append(f'API_BASE_URL: {api_base_url}')
            lines.extend([
                '', 'COMPLETENESS_COUNTS:', *[f'  {k}: {v}' for k, v in completeness.items()], '',
                f'RESULT: PASS - DPA {app_version()} bundles audited {meta.get("database_version")} '
                f'Schema {meta.get("schema_version")} with exactly 31 official provinces.',
            ])
            proof_path.parent.mkdir(parents=True, exist_ok=True)
            proof_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            print(proof_path.read_text(encoding='utf-8'))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('apk', type=Path)
    ap.add_argument('proof', type=Path)
    ap.add_argument('--api-base-url', default='')
    a = ap.parse_args()
    main(a.apk, a.proof, a.api_base_url)
