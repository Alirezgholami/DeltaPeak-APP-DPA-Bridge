#!/usr/bin/env python3
import argparse, json, sqlite3, hashlib, re
from pathlib import Path
from datetime import datetime, timezone

FIELD_MAP = {
    'رشته\u200cکوه': ('peaks', 'mountain_range'),
    'شهرستان': ('peaks', 'county'),
    'بخش/دهستان': ('peaks', 'district'),
    'عرض جغرافیایی': ('peaks', 'latitude'),
    'طول جغرافیایی': ('peaks', 'longitude'),
    'ارتفاع قله (Map)': ('peaks', 'map_elevation'),
    'مسیر اصلی صعود': ('peaks', 'route'),
    'نقطه شروع مسیر': ('peaks', 'trailhead'),
    'ارتفاع نقطه شروع (متر)': ('peaks', 'trailhead_elevation_m'),
    'طول مسیر (کیلومتر)': ('peaks', 'route_length_km'),
    'زمان صعود': ('peaks', 'ascent_time'),
    'زمان رفت\u200cوبرگشت': ('peaks', 'roundtrip_time'),
    'درجه سختی': ('peaks', 'difficulty'),
    'بهترین فصل صعود': ('peaks', 'best_season'),
    'نیاز به راهنما': ('peaks', 'guide_required'),
    'وضعیت مسیر': ('peaks', 'route_status'),
    'ارتفاع\u200cگیری مسیر/GPX (متر)': ('route_or_peak', 'elevation_gain_m'),
    'عرض جغرافیایی شروع پاکوب': ('route', 'trailhead_latitude'),
    'طول جغرافیایی شروع پاکوب': ('route', 'trailhead_longitude'),
}

def empty(v):
    return v is None or (isinstance(v, str) and not v.strip())

def normalize(s):
    return ' '.join((s or '').strip().replace('ي','ی').replace('ك','ک').split())

def now_utc():
    return datetime.now(timezone.utc).isoformat()

def ensure_tables(con):
    con.execute('''CREATE TABLE IF NOT EXISTS data_migrations (
        migration_id TEXT PRIMARY KEY,
        source_label TEXT NOT NULL,
        applied_at_utc TEXT NOT NULL,
        changed_fields INTEGER NOT NULL DEFAULT 0,
        inserted_routes INTEGER NOT NULL DEFAULT 0
    )''')

def refresh_search_text(con, peak_id):
    row=con.execute('SELECT name,aliases,local_alias,province,county,mountain_range FROM peaks WHERE id=?',(peak_id,)).fetchone()
    if not row: return
    text=normalize(' '.join(str(x) for x in row if x not in (None,'')))
    con.execute('UPDATE peaks SET search_text=? WHERE id=?',(text,peak_id))

def batch_tag(patch_id: str) -> str:
    m=re.search(r'B\d{2}', patch_id or '')
    return m.group(0) if m else 'PATCH'

def migration_id_for(patch_id: str) -> str:
    tag=batch_tag(patch_id)
    if tag=='B09': return 'REF-V390-B09'
    if tag=='B10': return 'REF-V391-B10'
    return f'REF-{tag}'

def source_label_for(patch_id: str) -> str:
    return f'DPD v3.91 {batch_tag(patch_id)}'

def apply_patch(db_path, patch_path, database_version, dataset_revision, source_workbook=None):
    patch=json.loads(Path(patch_path).read_text(encoding='utf-8'))
    con=sqlite3.connect(db_path)
    con.row_factory=sqlite3.Row
    ensure_tables(con)
    prior_schema_row=con.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()
    prior_schema=int(prior_schema_row[0]) if prior_schema_row and str(prior_schema_row[0]).isdigit() else 0
    patch_id=patch.get('patch_id','DPD-PATCH')
    tag=batch_tag(patch_id)
    changed=0; inserted_routes=0; skipped=0
    touched=set()
    with con:
        for item in patch.get('peak_field_updates',[]):
            if item.get('وضعیت') != 'آماده Merge':
                continue
            pid=item['شناسه NPC']; field=item['فیلد']; value=item.get('مقدار پیشنهادی')
            mapping=FIELD_MAP.get(field)
            if not mapping:
                skipped+=1; continue
            table,col=mapping
            peak=con.execute('SELECT id FROM peaks WHERE id=?',(pid,)).fetchone()
            if not peak:
                skipped+=1; continue
            if table=='peaks':
                cur=con.execute(f'SELECT {col} FROM peaks WHERE id=?',(pid,)).fetchone()[0]
                if empty(cur):
                    con.execute(f'UPDATE peaks SET {col}=? WHERE id=?',(value,pid)); changed+=1; touched.add(pid)
                    if col in ('latitude','longitude'):
                        src=item.get('منبع')
                        cs=con.execute('SELECT coordinate_source FROM peaks WHERE id=?',(pid,)).fetchone()[0]
                        if empty(cs) and src:
                            con.execute('UPDATE peaks SET coordinate_source=? WHERE id=?',(src,pid))
            elif table=='route':
                route=con.execute(f'SELECT route_id,{col} FROM gpx_routes WHERE peak_id=? AND is_deleted=0 ORDER BY route_id LIMIT 1',(pid,)).fetchone()
                if route and empty(route[col]):
                    con.execute(f'UPDATE gpx_routes SET {col}=? WHERE route_id=?',(value,route['route_id'])); changed+=1
            elif table=='route_or_peak':
                route=con.execute('SELECT route_id,elevation_gain_m FROM gpx_routes WHERE peak_id=? AND is_deleted=0 ORDER BY route_id LIMIT 1',(pid,)).fetchone()
                if route and empty(route['elevation_gain_m']):
                    con.execute('UPDATE gpx_routes SET elevation_gain_m=? WHERE route_id=?',(value,route['route_id'])); changed+=1
                prow=con.execute('SELECT elevation_gain_m FROM peaks WHERE id=?',(pid,)).fetchone()
                if prow and empty(prow[0]):
                    con.execute('UPDATE peaks SET elevation_gain_m=? WHERE id=?',(value,pid)); changed+=1; touched.add(pid)

        for idx, r in enumerate(patch.get('route_candidates',[]), start=1):
            pid=r['شناسه NPC']
            if not con.execute('SELECT 1 FROM peaks WHERE id=?',(pid,)).fetchone():
                skipped+=1; continue
            route_id=f"RCAND-{pid.replace('NPC-','')}-{tag}-{idx:02d}"
            if con.execute('SELECT 1 FROM gpx_routes WHERE route_id=?',(route_id,)).fetchone():
                continue
            route_type=r.get('نوع مسیر') or 'candidate'
            trailhead=r.get('Trailhead') or r.get('نقطه شروع مسیر')
            difficulty=r.get('درجه سختی')
            source_label=source_label_for(patch_id)
            flags=['candidate_route','needs_gpx_validation','missing_gpx_file']
            if r.get('Start Lat') is None or r.get('Start Lon') is None:
                flags.append('missing_trailhead_coordinates')
            con.execute('''INSERT INTO gpx_routes(
                route_id,peak_id,name,gpx_file_path,route_length_km,elevation_gain_m,
                trailhead,trailhead_latitude,trailhead_longitude,trailhead_elevation_m,
                source_owner,source_url,price_irr,currency,publication_status,download_count,
                route_count_hint,difficulty,estimated_duration,best_season,route_type,file_sha256,
                data_flags,version,is_deleted,created_at_utc,created_at_jalali,updated_at_utc,updated_at_jalali
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',(
                route_id,pid,r.get('نام مسیر'),None,r.get('طول مسیر (km)'),r.get('ارتفاع\u200cگیری (m)'),
                trailhead,r.get('Start Lat'),r.get('Start Lon'),r.get('Start Elev (m)'),
                source_label,r.get('منبع'),0,'IRR','draft',0,max(int(r.get('تعداد مسیرها') or 1),1),
                difficulty,r.get('مدت'),r.get('بهترین فصل'),route_type,None,
                ','.join(flags),1,0,now_utc(),None,now_utc(),None
            ))
            inserted_routes+=1

        for pid in touched:
            refresh_search_text(con,pid)

        # route_count represents actual route records available in the app.
        con.execute('''UPDATE peaks SET route_count=(SELECT COUNT(*) FROM gpx_routes r WHERE r.peak_id=peaks.id AND r.is_deleted=0)''')

        peak_rows=con.execute('SELECT id,latitude,longitude,mountain_range,map_elevation,elevation,status FROM peaks').fetchall()
        for prow in peak_rows:
            flags=[]
            if prow['latitude'] is None or prow['longitude'] is None: flags.append('missing_coordinates')
            if empty(prow['mountain_range']): flags.append('missing_mountain_range')
            if prow['map_elevation'] is None: flags.append('missing_map_elevation')
            if prow['elevation'] is None: flags.append('missing_summit_sign_elevation')
            status=(prow['status'] or '').upper()
            uncertain=any(x in status for x in ('AMBIG','UNRESOLVED','P4-','P3 FEATURE','AWAITING'))
            if uncertain: flags.append('needs_manual_review')
            quality='complete' if not flags else ('needs_review' if uncertain else 'incomplete')
            con.execute('UPDATE peaks SET data_flags=?,data_quality_status=? WHERE id=?',
                        (','.join(flags) if flags else None, quality, prow['id']))

        route_rows=con.execute('SELECT route_id,trailhead_latitude,trailhead_longitude,gpx_file_path,data_flags FROM gpx_routes').fetchall()
        for rrow in route_rows:
            existing=(rrow['data_flags'] or '').split(',') if rrow['data_flags'] else []
            preserved=[f for f in existing if f in ('candidate_route','needs_gpx_validation')]
            flags=list(preserved)
            if rrow['trailhead_latitude'] is None or rrow['trailhead_longitude'] is None: flags.append('missing_trailhead_coordinates')
            if empty(rrow['gpx_file_path']): flags.append('missing_gpx_file')
            con.execute('UPDATE gpx_routes SET data_flags=? WHERE route_id=?',
                        (','.join(dict.fromkeys(flags)) if flags else None, rrow['route_id']))

        prior_source=con.execute("SELECT value FROM metadata WHERE key='database_source_file'").fetchone()
        prior_source=prior_source[0] if prior_source else 'DeltaPeakDatabase_V3_90_GPXConsolidation_Master.xlsx'
        if source_workbook:
            parts=[x.strip() for x in prior_source.split(' + ') if x.strip()]
            if source_workbook not in parts:
                parts.append(source_workbook)
            source_file=' + '.join(parts)
        else:
            source_file=prior_source
        metadata={
            'database_version':database_version,
            'schema_version':'5',
            'dataset_revision':dataset_revision,
            'database_source_file':source_file,
            'enrichment_patch_id':patch_id,
            'enrichment_patch_sha256':hashlib.sha256(Path(patch_path).read_bytes()).hexdigest(),
            f'enrichment_patch_{tag.lower()}_sha256':hashlib.sha256(Path(patch_path).read_bytes()).hexdigest(),
            'enriched_at_utc':now_utc(),
            'route_scaffold_count':str(con.execute('SELECT COUNT(*) FROM gpx_routes WHERE is_deleted=0').fetchone()[0]),
        }
        for k,v in metadata.items():
            con.execute('INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)',(k,str(v)))
        jalali=con.execute("SELECT value FROM metadata WHERE key='generated_at_jalali'").fetchone()
        jalali_value=jalali[0] if jalali else 'migration'
        if prior_schema < 5:
            con.execute('INSERT OR IGNORE INTO schema_migrations(migration_id,from_schema,to_schema,applied_at_utc,applied_at_jalali) VALUES(?,?,?,?,?)',
                        (f'S{prior_schema}-S5-DATA-{tag}', prior_schema, 5, now_utc(), jalali_value))
        con.execute('INSERT OR REPLACE INTO data_migrations(migration_id,source_label,applied_at_utc,changed_fields,inserted_routes) VALUES(?,?,?,?,?)',
                    (migration_id_for(patch_id), patch_id, now_utc(), changed, inserted_routes))

    ok=con.execute('PRAGMA integrity_check').fetchone()[0]
    if ok!='ok': raise SystemExit(f'integrity_check failed: {ok}')
    counts={
        'peaks':con.execute('SELECT COUNT(*) FROM peaks WHERE is_deleted=0').fetchone()[0],
        'routes':con.execute('SELECT COUNT(*) FROM gpx_routes WHERE is_deleted=0').fetchone()[0],
        'description':con.execute("SELECT COUNT(*) FROM peaks WHERE is_deleted=0 AND description IS NOT NULL AND TRIM(description)<>''").fetchone()[0],
        'mountain_range':con.execute("SELECT COUNT(*) FROM peaks WHERE is_deleted=0 AND mountain_range IS NOT NULL AND TRIM(mountain_range)<>''").fetchone()[0],
        'coordinates':con.execute('SELECT COUNT(*) FROM peaks WHERE is_deleted=0 AND latitude IS NOT NULL AND longitude IS NOT NULL').fetchone()[0],
        'trailhead_coordinates':con.execute('SELECT COUNT(*) FROM gpx_routes WHERE is_deleted=0 AND trailhead_latitude IS NOT NULL AND trailhead_longitude IS NOT NULL').fetchone()[0],
    }
    con.close()
    print(json.dumps({'patch_id':patch_id,'changed_fields':changed,'inserted_routes':inserted_routes,'skipped':skipped,'counts':counts},ensure_ascii=False))

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('database')
    ap.add_argument('patch')
    ap.add_argument('--database-version',default='DPD v3.90 + v3.91 enrichment')
    ap.add_argument('--dataset-revision',default='v390-v391-enrichment-safe-overlay')
    ap.add_argument('--source-workbook')
    a=ap.parse_args()
    apply_patch(a.database,a.patch,a.database_version,a.dataset_revision,a.source_workbook)
