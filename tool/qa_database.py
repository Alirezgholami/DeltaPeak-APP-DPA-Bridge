#!/usr/bin/env python3
import sqlite3
import sys
from pathlib import Path

EXPECTED_VERSION = 'DPD v3.90 + v3.91 enrichment B10'
EXPECTED_SCHEMA = '5'
EXPECTED_DATASET_REVISION = 'v390-v391b10-corefields-v2'
EXPECTED_SOURCE_RECORDS = 2000
EXPECTED_RECORDS = 1999
EXPECTED_EXCLUSIONS = 1
EXPECTED_ROUTE_SCAFFOLDS = 919
EXPECTED_EDU_CATEGORIES = 6
EXPECTED_EDU_CONTENTS = 42
EXPECTED_SOURCE_FILE = 'DeltaPeakDatabase_V3_90_GPXConsolidation_Master.xlsx + DeltaPeakDatabase_V3_91_EnrichmentPatch_Batch09.xlsx + DeltaPeakDatabase_V3_91_EnrichmentPatch_Batch10.xlsx'
EXPECTED_SOURCE_SHA256 = '20fb7302a16447fd5383a96d51e6fa5a118c20ae542c7d16b4e19e4ec54398a0'
REQUIRED_PEAK_COLUMNS = {
    'id','province','name','aliases','elevation','map_elevation','reported_elevations',
    'source_occurrence_count','source','raw_text_sample','source_url','status',
    'county','district','latitude','longitude','coordinate_source','route','trailhead',
    'trailhead_elevation_m','elevation_gain_m','route_length_km','ascent_time',
    'roundtrip_time','difficulty','best_season','guide_required','route_status',
    'local_alias','route_count','mountain_range','description','data_flags','data_quality_status','search_text','favorite',
    'is_deleted','created_at_utc','created_at_jalali','updated_at_utc','updated_at_jalali',
    'deleted_at_utc','deleted_at_jalali'
}
REQUIRED_TABLES = {
    'metadata','peaks','source_exclusions','audit_log','gpx_routes','users','wallets',
    'payment_profiles','orders','payments','gpx_purchases','transactions','download_entitlements','download_events',
    'discount_codes','route_owners','route_revenue_shares','education_categories',
    'education_contents','app_settings','schema_migrations','data_migrations','backup_history','sync_outbox'
}
OFFICIAL_PROVINCES = {
    'آذربایجان شرقی','آذربایجان غربی','اردبیل','اصفهان','البرز','ایلام','بوشهر','تهران',
    'خراسان جنوبی','خراسان رضوی','خراسان شمالی','خوزستان','زنجان','سمنان','سیستان و بلوچستان',
    'فارس','قزوین','قم','لرستان','مازندران','مرکزی','هرمزگان','همدان','چهارمحال و بختیاری',
    'کردستان','کرمان','کرمانشاه','کهگیلویه و بویراحمد','گلستان','گیلان','یزد'
}
SENTINELS = {
    'NPC-E186BE44AA': ('مازندران', 'دماوند', 5610),
    'NPC-DE1A5C2E5E': ('تهران', 'توچال', 3963),
    'NPC-9755C69061': ('اردبیل', 'سبلان', 4811),
}


def fail(msg: str):
    raise SystemExit(f'DPA DATABASE QA FAILED: {msg}')


def main(path: str):
    db_path = Path(path)
    if not db_path.exists() or db_path.stat().st_size < 100_000:
        fail(f'database missing or unexpectedly small: {db_path}')

    db = sqlite3.connect(db_path)
    try:
        db.execute('PRAGMA foreign_keys=ON')
        integrity = db.execute('PRAGMA integrity_check').fetchone()[0]
        if integrity != 'ok':
            fail(f'integrity_check={integrity!r}')
        fk_errors = db.execute('PRAGMA foreign_key_check').fetchall()
        if fk_errors:
            fail(f'foreign_key_check errors: {fk_errors[:5]}')

        tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        missing_tables = REQUIRED_TABLES - tables
        if missing_tables:
            fail(f'missing required tables: {sorted(missing_tables)}')

        meta = dict(db.execute('SELECT key,value FROM metadata'))
        expected_meta = {
            'database_version': EXPECTED_VERSION,
            'schema_version': EXPECTED_SCHEMA,
            'dataset_revision': EXPECTED_DATASET_REVISION,
            'database_source_file': EXPECTED_SOURCE_FILE,
            'database_source_sha256': EXPECTED_SOURCE_SHA256,
        }
        for key, expected in expected_meta.items():
            if meta.get(key) != expected:
                fail(f'{key}={meta.get(key)!r}, expected {expected!r}')

        if int(meta.get('source_record_count', '-1')) != EXPECTED_SOURCE_RECORDS:
            fail('source_record_count mismatch')
        if int(meta.get('record_count', '-1')) != EXPECTED_RECORDS:
            fail('metadata record_count mismatch')
        if int(meta.get('controlled_exclusion_count', '-1')) != EXPECTED_EXCLUSIONS:
            fail('controlled_exclusion_count mismatch')
        if int(meta.get('route_scaffold_count', '-1')) != EXPECTED_ROUTE_SCAFFOLDS:
            fail('route_scaffold_count mismatch')
        if not meta.get('generated_at_utc') or not meta.get('generated_at_jalali'):
            fail('generated timestamps missing')

        count = db.execute('SELECT COUNT(*) FROM peaks').fetchone()[0]
        if count != EXPECTED_RECORDS:
            fail(f'record_count={count}, expected {EXPECTED_RECORDS}')
        distinct_ids = db.execute('SELECT COUNT(DISTINCT id) FROM peaks').fetchone()[0]
        if distinct_ids != count:
            fail(f'duplicate/non-unique ids detected: rows={count}, distinct_ids={distinct_ids}')

        columns = {r[1] for r in db.execute('PRAGMA table_info(peaks)')}
        missing = REQUIRED_PEAK_COLUMNS - columns
        if missing:
            fail(f'missing peak columns: {sorted(missing)}')

        route_columns = {r[1] for r in db.execute('PRAGMA table_info(gpx_routes)')}
        for required in {'trailhead_latitude','trailhead_longitude','file_sha256','data_flags'}:
            if required not in route_columns:
                fail(f'missing gpx_routes column: {required}')

        user_columns = {r[1] for r in db.execute('PRAGMA table_info(users)')}
        for required in {'role','last_login_at_utc','last_login_at_jalali','last_activity_at_utc','last_activity_at_jalali'}:
            if required not in user_columns:
                fail(f'missing users column: {required}')
        forbidden_user_columns = {c for c in user_columns if any(x in c.lower() for x in ('password','passwd','otp','token','secret'))}
        if forbidden_user_columns:
            fail(f'authentication secrets must not exist in SQLite users table: {sorted(forbidden_user_columns)}')

        migration_count = db.execute('SELECT COUNT(*) FROM schema_migrations WHERE to_schema=5').fetchone()[0]
        if migration_count < 1:
            fail('Schema 5 migration marker missing')
        b09_marker = db.execute("SELECT source_label,changed_fields,inserted_routes FROM data_migrations WHERE migration_id='REF-V390-B09'").fetchone()
        if b09_marker is None:
            fail('reference data migration marker REF-V390-B09 missing')
        b10_marker = db.execute("SELECT source_label,changed_fields,inserted_routes FROM data_migrations WHERE migration_id='REF-V391-B10'").fetchone()
        if b10_marker is None:
            fail('reference data migration marker REF-V391-B10 missing')
        if meta.get('enrichment_patch_id') != 'DPD-V3.91-B10-CoreFields':
            fail(f"enrichment_patch_id={meta.get('enrichment_patch_id')!r}")

        provinces = {r[0] for r in db.execute('SELECT DISTINCT province FROM peaks WHERE is_deleted=0')}
        missing_provinces = OFFICIAL_PROVINCES - provinces
        extra_provinces = provinces - OFFICIAL_PROVINCES
        if missing_provinces:
            fail(f'missing official provinces: {sorted(missing_provinces)}')
        if extra_provinces:
            fail(f'non-official/shared province labels remain: {sorted(extra_provinces)}')
        if len(provinces) != 31:
            fail(f'province label count={len(provinces)}, expected exactly 31')

        yurd = db.execute("SELECT COUNT(*) FROM peaks WHERE id='NPC-38EF3442EC'").fetchone()[0]
        if yurd:
            fail('non-canonical combined Yurd source record is still present')
        exclusion = db.execute(
            "SELECT source_name,source_province,reason FROM source_exclusions WHERE source_id='NPC-38EF3442EC'"
        ).fetchone()
        if exclusion is None or exclusion[0] != 'یورد':
            fail('controlled Yurd source exclusion is missing')

        invalid_coords = db.execute('''
          SELECT COUNT(*) FROM peaks
          WHERE (latitude IS NOT NULL AND (latitude < 20 OR latitude > 45))
             OR (longitude IS NOT NULL AND (longitude < 40 OR longitude > 65))
        ''').fetchone()[0]
        if invalid_coords:
            fail(f'{invalid_coords} coordinates outside Iran sanity bounds')

        thresholds = {
            'elevation': 1800, 'county': 300, 'latitude': 1250, 'route': 600,
            'trailhead': 300, 'trailhead_elevation_m': 100,
            'elevation_gain_m': 110, 'route_length_km': 120,
        }
        for field, minimum in thresholds.items():
            n = db.execute(
                f"SELECT COUNT(*) FROM peaks WHERE is_deleted=0 AND {field} IS NOT NULL AND TRIM(CAST({field} AS TEXT))<>''"
            ).fetchone()[0]
            if n < minimum:
                fail(f'{field} completeness too low: {n} < {minimum}')

        map_elevation_count = db.execute('SELECT COUNT(*) FROM peaks WHERE map_elevation IS NOT NULL').fetchone()[0]
        if map_elevation_count < 200:
            fail(f'explicit map elevation extraction unexpectedly low: {map_elevation_count}')
        mountain_range_count = db.execute("SELECT COUNT(*) FROM peaks WHERE mountain_range IS NOT NULL AND TRIM(mountain_range)<>''").fetchone()[0]
        if mountain_range_count < 50:
            fail(f'explicit mountain range extraction unexpectedly low: {mountain_range_count}')
        description_count = db.execute("SELECT COUNT(*) FROM peaks WHERE description IS NOT NULL AND TRIM(description)<>''").fetchone()[0]
        if description_count < 1990:
            fail(f'description completeness unexpectedly low: {description_count}')
        trailhead_coordinate_count = db.execute('SELECT COUNT(*) FROM gpx_routes WHERE trailhead_latitude IS NOT NULL AND trailhead_longitude IS NOT NULL').fetchone()[0]
        if trailhead_coordinate_count < 100:
            fail(f'trailhead coordinate completeness unexpectedly low: {trailhead_coordinate_count}')

        invalid_quality = db.execute("SELECT COUNT(*) FROM peaks WHERE data_quality_status NOT IN ('complete','incomplete','needs_review')").fetchone()[0]
        if invalid_quality:
            fail(f'invalid data_quality_status rows={invalid_quality}')
        missing_range = db.execute("SELECT COUNT(*) FROM peaks WHERE mountain_range IS NULL OR TRIM(mountain_range)=''").fetchone()[0]
        flagged_range = db.execute("SELECT COUNT(*) FROM peaks WHERE (mountain_range IS NULL OR TRIM(mountain_range)='') AND data_flags LIKE '%missing_mountain_range%'").fetchone()[0]
        if missing_range != flagged_range:
            fail(f'missing mountain_range rows are not fully flagged: missing={missing_range}, flagged={flagged_range}')
        missing_coords = db.execute('SELECT COUNT(*) FROM peaks WHERE latitude IS NULL OR longitude IS NULL').fetchone()[0]
        flagged_coords = db.execute("SELECT COUNT(*) FROM peaks WHERE (latitude IS NULL OR longitude IS NULL) AND data_flags LIKE '%missing_coordinates%'").fetchone()[0]
        if missing_coords != flagged_coords:
            fail(f'missing coordinate rows are not fully flagged: missing={missing_coords}, flagged={flagged_coords}')

        route_count = db.execute('SELECT COUNT(*) FROM gpx_routes').fetchone()[0]
        if route_count != EXPECTED_ROUTE_SCAFFOLDS:
            fail(f'route scaffolds={route_count}, expected {EXPECTED_ROUTE_SCAFFOLDS}')
        orphan_routes = db.execute('''
          SELECT COUNT(*) FROM gpx_routes r LEFT JOIN peaks p ON p.id=r.peak_id
          WHERE p.id IS NULL
        ''').fetchone()[0]
        if orphan_routes:
            fail(f'orphan routes={orphan_routes}')
        bad_prices = db.execute('SELECT COUNT(*) FROM gpx_routes WHERE price_irr < 0').fetchone()[0]
        if bad_prices:
            fail(f'negative route prices={bad_prices}')

        edu_cats = db.execute('SELECT COUNT(*) FROM education_categories WHERE is_active=1').fetchone()[0]
        edu_items = db.execute("SELECT COUNT(*) FROM education_contents WHERE publication_status='published'").fetchone()[0]
        if edu_cats != EXPECTED_EDU_CATEGORIES or edu_items != EXPECTED_EDU_CONTENTS:
            fail(f'education seed mismatch: categories={edu_cats}, contents={edu_items}')
        if meta.get('education_revision') != 'edu-v1-20260912':
            fail(f"education_revision={meta.get('education_revision')!r}, expected 'edu-v1-20260912'")
        if int(meta.get('education_content_count', '-1')) != EXPECTED_EDU_CONTENTS:
            fail('education_content_count metadata mismatch')
        legacy_edu = db.execute("SELECT COUNT(*) FROM education_contents WHERE content_id LIKE 'EDU-ART-%'").fetchone()[0]
        if legacy_edu:
            fail(f'legacy placeholder education rows remain: {legacy_edu}')
        per_category = dict(db.execute("SELECT category_id,COUNT(*) FROM education_contents WHERE publication_status='published' GROUP BY category_id"))
        expected_per_category = {'EDU-CAT-01': 6, 'EDU-CAT-02': 6, 'EDU-CAT-03': 9, 'EDU-CAT-04': 7, 'EDU-CAT-05': 7, 'EDU-CAT-06': 7}
        if per_category != expected_per_category:
            fail(f'education distribution mismatch: {per_category!r}')
        edu_marker = db.execute("SELECT COUNT(*) FROM data_migrations WHERE migration_id='EDU-V1-20260912'").fetchone()[0]
        if edu_marker != 1:
            fail('education migration marker missing')

        for peak_id, expected in SENTINELS.items():
            row = db.execute('SELECT province,name,elevation FROM peaks WHERE id=?', (peak_id,)).fetchone()
            if row is None:
                fail(f'missing sentinel peak {peak_id}')
            got = (row[0], row[1], row[2])
            if got != expected:
                fail(f'sentinel mismatch for {peak_id}: {got!r} != {expected!r}')

        print('DPA DATABASE QA PASSED')
        print(f'  version: {meta["database_version"]}')
        print(f'  schema: {meta["schema_version"]}')
        print(f'  dataset: {meta["dataset_revision"]}')
        print(f'  source records: {meta["source_record_count"]}')
        print(f'  publishable peaks: {count}')
        print(f'  controlled exclusions: {meta["controlled_exclusion_count"]}')
        print(f'  GPX route scaffolds: {route_count}')
        print(f'  education: {edu_cats} categories / {edu_items} contents')
        print(f'  province labels: {len(provinces)} (exactly 31 official provinces)')
        print(f'  generated (Jalali): {meta.get("generated_at_jalali")}')
        print('  accounts/data safety: roles + schema/data migration + backup + sync-outbox schema verified')
        print('  sentinels: Damavand / Tochal / Sabalan verified')
    finally:
        db.close()


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: qa_database.py assets/peaks.db')
    main(sys.argv[1])
