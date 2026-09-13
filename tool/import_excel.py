#!/usr/bin/env python3
"""Build DPA SQLite Schema 5 from audited DPD v3.88 using Python stdlib only."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import re
import sqlite3
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
NS_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS_PKG_REL = 'http://schemas.openxmlformats.org/package/2006/relationships'

OFFICIAL_PROVINCES = [
    'آذربایجان شرقی','آذربایجان غربی','اردبیل','اصفهان','البرز','ایلام','بوشهر','تهران',
    'چهارمحال و بختیاری','خراسان جنوبی','خراسان رضوی','خراسان شمالی','خوزستان','زنجان','سمنان',
    'سیستان و بلوچستان','فارس','قزوین','قم','کردستان','کرمان','کرمانشاه','کهگیلویه و بویراحمد',
    'گلستان','گیلان','لرستان','مازندران','مرکزی','هرمزگان','همدان','یزد'
]

DATASET_REVISION = 'v390-corefields-import-v2'
SCHEMA_VERSION = '5'

PROVINCE_OVERRIDES = {
    'NPC-FCD993A458': 'تهران', 'NPC-4DCCB9EC4F': 'تهران',
    'NPC-B2DDF996D1': 'تهران', 'NPC-06673FC3B5': 'تهران',
    'NPC-5D75537E17': 'تهران', 'NPC-57D0A18E00': 'تهران',
    'NPC-9DA2D2B5B8': 'تهران', 'NPC-27510B70EF': 'تهران',
    'NPC-34CA619556': 'تهران',
    'NPC-F79C3E0D31': 'مازندران', 'NPC-55A521E459': 'مازندران',
    'NPC-F63946E15D': 'مازندران', 'NPC-06C593AB52': 'مازندران',
    'NPC-85AEEE9A24': 'مازندران', 'NPC-09E016596F': 'مازندران',
    'NPC-338FE9BB41': 'مازندران', 'NPC-47588AAA6C': 'مازندران',
    'NPC-17B599E264': 'مازندران', 'NPC-7DB2317AF0': 'مازندران',
    'NPC-A39C534B26': 'مازندران', 'NPC-A2B7F7F9B3': 'مازندران',
    'NPC-EC9C62C959': 'تهران', 'NPC-C935D71BB6': 'تهران',
    'NPC-370FA350E8': 'خراسان رضوی',
}

EXCLUDED_APP_RECORDS = {
    'NPC-38EF3442EC': 'non-canonical combined source record; source province is چنداستانی (سمنان / تهران)',
}

EDUCATION_PACK = Path(__file__).resolve().parents[1] / 'assets' / 'education_v1.json'


def load_education_pack() -> dict:
    data = json.loads(EDUCATION_PACK.read_text(encoding='utf-8'))
    if data.get('revision') != 'edu-v1-20260912':
        raise SystemExit(f'Unexpected education revision: {data.get("revision")!r}')
    if len(data.get('categories', [])) != 6 or len(data.get('contents', [])) != 42:
        raise SystemExit('Education pack must contain 6 categories and 42 contents')
    return data


def col_index(ref: str) -> int:
    m = re.match(r'([A-Z]+)', ref)
    if not m:
        raise ValueError(f'Invalid cell reference: {ref}')
    n = 0
    for ch in m.group(1):
        n = n * 26 + ord(ch) - 64
    return n - 1


def shared_strings(zf: zipfile.ZipFile) -> list[str]:
    try:
        root = ET.fromstring(zf.read('xl/sharedStrings.xml'))
    except KeyError:
        return []
    return [''.join(node.text or '' for node in si.iter(f'{{{NS_MAIN}}}t'))
            for si in root.findall(f'{{{NS_MAIN}}}si')]


def sheet_path(zf: zipfile.ZipFile, sheet_name: str) -> str:
    workbook = ET.fromstring(zf.read('xl/workbook.xml'))
    rid = None
    for sheet in workbook.find(f'{{{NS_MAIN}}}sheets'):
        if sheet.attrib.get('name') == sheet_name:
            rid = sheet.attrib.get(f'{{{NS_REL}}}id')
            break
    if rid is None:
        raise KeyError(f'Sheet not found: {sheet_name}')
    rels = ET.fromstring(zf.read('xl/_rels/workbook.xml.rels'))
    target = None
    for rel in rels.findall(f'{{{NS_PKG_REL}}}Relationship'):
        if rel.attrib.get('Id') == rid:
            target = rel.attrib['Target']
            break
    if target is None:
        raise KeyError(f'Relationship not found for sheet: {sheet_name}')
    target = target.lstrip('/')
    return target if target.startswith('xl/') else f'xl/{target}'


def read_registry(path: Path) -> list[list[object | None]]:
    with zipfile.ZipFile(path) as zf:
        strings = shared_strings(zf)
        root = ET.fromstring(zf.read(sheet_path(zf, 'رجیستری ملی')))
        rows_out: list[list[object | None]] = []
        for row in root.iter(f'{{{NS_MAIN}}}row'):
            cells: dict[int, object | None] = {}
            max_col = -1
            for cell in row.findall(f'{{{NS_MAIN}}}c'):
                ci = col_index(cell.attrib.get('r', 'A1'))
                max_col = max(max_col, ci)
                kind = cell.attrib.get('t')
                v = cell.find(f'{{{NS_MAIN}}}v')
                if kind == 'inlineStr':
                    is_node = cell.find(f'{{{NS_MAIN}}}is')
                    value = ''.join((t.text or '') for t in is_node.iter(f'{{{NS_MAIN}}}t')) if is_node is not None else ''
                elif v is None:
                    value = None
                elif kind == 's':
                    value = strings[int(v.text)]
                elif kind in ('str', 'e'):
                    value = v.text
                elif kind == 'b':
                    value = v.text == '1'
                else:
                    text = v.text or ''
                    try:
                        number = float(text)
                        value = int(number) if number.is_integer() else number
                    except ValueError:
                        value = text
                cells[ci] = value
            if max_col >= 0:
                row_values = [None] * (max_col + 1)
                for ci, value in cells.items():
                    row_values[ci] = value
                rows_out.append(row_values)
        return rows_out


def clean(value):
    if value is None:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value


PERSIAN_DIGITS = str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩', '01234567890123456789')
ARABIC_DIACRITICS_RE = re.compile(r'[\u064B-\u065F\u0670\u06D6-\u06ED]')


def normalize_digits(value) -> str:
    return str(value).translate(PERSIAN_DIGITS).replace('٬', '').replace('٫', '.').replace('−', '-')


def to_int(value):
    value = clean(value)
    if value is None:
        return None
    try:
        return int(float(normalize_digits(value).replace(',', '.')))
    except (TypeError, ValueError):
        return None


def to_float(value):
    value = clean(value)
    if value is None:
        return None
    try:
        return float(normalize_digits(value).replace(',', '.'))
    except (TypeError, ValueError):
        return None


def normalize(value: str) -> str:
    text = str(value).replace('\u00a0', ' ').replace('\u202f', ' ')
    replacements = {
        'ي': 'ی', 'ى': 'ی', 'ے': 'ی', 'ك': 'ک', 'ۀ': 'ه', 'ة': 'ه',
        'أ': 'ا', 'إ': 'ا', 'ٱ': 'ا', 'ـ': '',
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    text = ARABIC_DIACRITICS_RE.sub('', text)
    return re.sub(r'\s+', ' ', text).strip()


MAP_SOURCE_KEYS = ('mapcarta', 'geonames', 'osm', 'peakvisor', 'hilltop', 'gholleh', 'نقشه')
MAP_AMBIGUITY_KEYS = ('neighbor', 'هم‌نام جدا', 'هم نام جدا', 'همسایه', 'ناسازگار', 'عارضه جدا', 'فاصله', 'conflict')


def explicit_map_elevation(reported) -> int | None:
    """Return a map-source elevation only when DPD text gives one unambiguous value."""
    text = clean(reported)
    if text is None:
        return None
    candidates: list[int] = []
    for segment in re.split(r'[؛;]', str(text)):
        low = segment.lower()
        if not any(key in low for key in MAP_SOURCE_KEYS):
            continue
        if any(key in low for key in MAP_AMBIGUITY_KEYS):
            continue
        numbers = sorted({int(v) for v in re.findall(r'(?<!\d)([1-5]\d{3})(?!\d)', segment)})
        if len(numbers) == 1:
            candidates.append(numbers[0])
    unique = set(candidates)
    return next(iter(unique)) if len(unique) == 1 else None


EXPLICIT_RANGE_OVERRIDES = {
    # These values are named explicitly in DPD v3.88 audit text; they are not province inference.
    'NPC-B3B076D7FB': 'میشو',
    'NPC-C7C682F433': 'قندیل',
    'NPC-C3E7E678C6': 'الوند گلپایگان',
    'NPC-1C12E7E73C': 'دنا',
    'NPC-27510B70EF': 'قوچ/زاغ',
    'NPC-A0AA277180': 'توچال',
    'NPC-9DA2D2B5B8': 'قوچ/زاغ',
}


def explicit_mountain_range(peak_id: str, district, status) -> str | None:
    """Extract only an explicitly named range from audited DPD text; never infer by province."""
    if peak_id in EXPLICIT_RANGE_OVERRIDES:
        return EXPLICIT_RANGE_OVERRIDES[peak_id]
    district_text = str(clean(district) or '')
    # District/location notes are used only when they literally contain the range marker.
    match = re.search(r'رشته[‌ -]?کوه\s+([^/—؛،]+)', district_text)
    if match:
        value = normalize(match.group(1))
        if 1 <= len(value.split()) <= 4:
            return value
    match = re.search(r'(?:^|[؛،:]\s*)رشته\s+([^/—؛،]+)', district_text)
    if match:
        value = normalize(match.group(1))
        if 1 <= len(value.split()) <= 4 and not value.startswith('فرعی') and not value.startswith('جنوبی'):
            return value
    return None


def gregorian_to_jalali(gy: int, gm: int, gd: int) -> tuple[int, int, int]:
    gdm = [0,31,59,90,120,151,181,212,243,273,304,334]
    gy2 = gy + 1 if gm > 2 else gy
    days = 355666 + 365*gy + (gy2+3)//4 - (gy2+99)//100 + (gy2+399)//400 + gd + gdm[gm-1]
    jy = -1595 + 33*(days//12053)
    days %= 12053
    jy += 4*(days//1461)
    days %= 1461
    if days > 365:
        jy += (days-1)//365
        days = (days-1)%365
    if days < 186:
        jm, jd = 1 + days//31, 1 + days%31
    else:
        jm, jd = 7 + (days-186)//30, 1 + (days-186)%30
    return jy, jm, jd


def timestamp_pair(now: dt.datetime | None = None) -> tuple[str, str]:
    now = now or dt.datetime.now(dt.timezone.utc)
    utc = now.isoformat()
    local = now.astimezone(dt.timezone(dt.timedelta(hours=3, minutes=30)))
    jy, jm, jd = gregorian_to_jalali(local.year, local.month, local.day)
    jalali = f'{jy:04d}/{jm:02d}/{jd:02d} {local:%H:%M}'
    return utc, jalali


def create_schema(db: sqlite3.Connection):
    db.executescript('''
      PRAGMA foreign_keys=ON;
      CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE peaks (
        id TEXT PRIMARY KEY, province TEXT NOT NULL, name TEXT NOT NULL,
        aliases TEXT, elevation INTEGER, map_elevation INTEGER, reported_elevations TEXT,
        source_occurrence_count INTEGER, source TEXT, raw_text_sample TEXT,
        source_url TEXT, status TEXT, county TEXT, district TEXT,
        latitude REAL, longitude REAL, coordinate_source TEXT, route TEXT,
        trailhead TEXT, trailhead_elevation_m INTEGER, elevation_gain_m INTEGER,
        route_length_km REAL, ascent_time TEXT, roundtrip_time TEXT,
        difficulty TEXT, best_season TEXT, guide_required TEXT, route_status TEXT,
        local_alias TEXT, route_count INTEGER NOT NULL DEFAULT 0,
        mountain_range TEXT, description TEXT, data_flags TEXT,
        data_quality_status TEXT NOT NULL DEFAULT 'incomplete', search_text TEXT NOT NULL, favorite INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0 CHECK(is_deleted IN (0,1)),
        created_at_utc TEXT, created_at_jalali TEXT,
        updated_at_utc TEXT, updated_at_jalali TEXT,
        deleted_at_utc TEXT, deleted_at_jalali TEXT
      );
      CREATE INDEX peaks_province ON peaks(province);
      CREATE INDEX peaks_name ON peaks(name);
      CREATE INDEX peaks_county ON peaks(county);
      CREATE INDEX peaks_search_text ON peaks(search_text);
      CREATE INDEX peaks_deleted ON peaks(is_deleted);
      CREATE INDEX peaks_quality ON peaks(data_quality_status, is_deleted);

      CREATE TABLE source_exclusions (
        source_id TEXT PRIMARY KEY, source_name TEXT, source_province TEXT,
        reason TEXT NOT NULL, created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL
      );

      CREATE TABLE audit_log (
        audit_id INTEGER PRIMARY KEY AUTOINCREMENT, peak_id TEXT,
        entity_type TEXT NOT NULL DEFAULT 'peak', entity_id TEXT NOT NULL,
        action TEXT NOT NULL DEFAULT 'update', field_name TEXT,
        old_value TEXT, new_value TEXT, actor TEXT NOT NULL DEFAULT 'owner',
        changed_at_utc TEXT NOT NULL, changed_at_jalali TEXT NOT NULL
      );
      CREATE INDEX audit_entity_id ON audit_log(entity_type, entity_id);

      CREATE TABLE gpx_routes (
        route_id TEXT PRIMARY KEY, peak_id TEXT NOT NULL,
        name TEXT NOT NULL, gpx_file_path TEXT,
        route_length_km REAL, elevation_gain_m INTEGER,
        trailhead TEXT, trailhead_latitude REAL, trailhead_longitude REAL,
        trailhead_elevation_m INTEGER, source_owner TEXT, source_url TEXT,
        price_irr INTEGER NOT NULL DEFAULT 0 CHECK(price_irr >= 0),
        currency TEXT NOT NULL DEFAULT 'IRR', publication_status TEXT NOT NULL DEFAULT 'draft',
        download_count INTEGER NOT NULL DEFAULT 0, route_count_hint INTEGER NOT NULL DEFAULT 1,
        difficulty TEXT, estimated_duration TEXT, best_season TEXT,
        route_type TEXT, file_sha256 TEXT, data_flags TEXT, version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0 CHECK(is_deleted IN (0,1)),
        created_at_utc TEXT, created_at_jalali TEXT,
        updated_at_utc TEXT, updated_at_jalali TEXT,
        deleted_at_utc TEXT, deleted_at_jalali TEXT,
        FOREIGN KEY(peak_id) REFERENCES peaks(id)
      );
      CREATE INDEX routes_peak_id ON gpx_routes(peak_id);
      CREATE INDEX routes_publish ON gpx_routes(publication_status, is_deleted);
      CREATE INDEX routes_file_sha256 ON gpx_routes(file_sha256) WHERE file_sha256 IS NOT NULL AND file_sha256<>'';

      CREATE TABLE users (
        user_id TEXT PRIMARY KEY, display_name TEXT NOT NULL,
        mobile TEXT, email TEXT, status TEXT NOT NULL DEFAULT 'active',
        role TEXT NOT NULL DEFAULT 'user',
        last_login_at_utc TEXT, last_login_at_jalali TEXT,
        last_activity_at_utc TEXT, last_activity_at_jalali TEXT,
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL, updated_at_jalali TEXT NOT NULL
      );
      CREATE UNIQUE INDEX users_mobile_unique ON users(mobile) WHERE mobile IS NOT NULL AND mobile<>'';
      CREATE UNIQUE INDEX users_email_unique ON users(email) WHERE email IS NOT NULL AND email<>'';

      CREATE TABLE wallets (
        wallet_id TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE,
        balance_irr INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active',
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL, updated_at_jalali TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(user_id)
      );

      CREATE TABLE payment_profiles (
        payment_profile_id TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE,
        preferred_gateway TEXT, gateway_customer_ref TEXT,
        can_pay INTEGER NOT NULL DEFAULT 1, created_at_utc TEXT NOT NULL,
        created_at_jalali TEXT NOT NULL, updated_at_utc TEXT NOT NULL,
        updated_at_jalali TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(user_id)
      );

      CREATE TABLE orders (
        order_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, route_id TEXT NOT NULL,
        amount_irr INTEGER NOT NULL, discount_irr INTEGER NOT NULL DEFAULT 0,
        payable_irr INTEGER NOT NULL, payment_status TEXT NOT NULL DEFAULT 'pending',
        gateway TEXT, gateway_authority TEXT, gateway_reference TEXT,
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        paid_at_utc TEXT, paid_at_jalali TEXT,
        FOREIGN KEY(user_id) REFERENCES users(user_id),
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id)
      );
      CREATE UNIQUE INDEX one_pending_order_per_route_user
        ON orders(user_id, route_id) WHERE payment_status='pending';

      CREATE TABLE payments (
        payment_id TEXT PRIMARY KEY, order_id TEXT NOT NULL, user_id TEXT NOT NULL,
        amount_irr INTEGER NOT NULL, payment_status TEXT NOT NULL DEFAULT 'pending',
        gateway TEXT, authority_ref TEXT, reference_id TEXT, failure_message TEXT,
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        verified_at_utc TEXT, verified_at_jalali TEXT,
        FOREIGN KEY(order_id) REFERENCES orders(order_id),
        FOREIGN KEY(user_id) REFERENCES users(user_id)
      );

      CREATE TABLE gpx_purchases (
        purchase_id TEXT PRIMARY KEY, order_id TEXT NOT NULL UNIQUE, user_id TEXT NOT NULL,
        route_id TEXT NOT NULL, purchase_status TEXT NOT NULL DEFAULT 'pending',
        price_irr INTEGER NOT NULL, created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        completed_at_utc TEXT, completed_at_jalali TEXT,
        FOREIGN KEY(order_id) REFERENCES orders(order_id),
        FOREIGN KEY(user_id) REFERENCES users(user_id),
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id)
      );

      CREATE TABLE transactions (
        transaction_id TEXT PRIMARY KEY, user_id TEXT NOT NULL,
        order_id TEXT, route_id TEXT, transaction_type TEXT NOT NULL,
        amount_irr INTEGER NOT NULL, status TEXT NOT NULL,
        gateway TEXT, authority_ref TEXT, created_at_utc TEXT NOT NULL,
        created_at_jalali TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(user_id),
        FOREIGN KEY(order_id) REFERENCES orders(order_id),
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id)
      );

      CREATE TABLE download_entitlements (
        entitlement_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, route_id TEXT NOT NULL,
        order_id TEXT, status TEXT NOT NULL DEFAULT 'active',
        download_limit INTEGER, download_count INTEGER NOT NULL DEFAULT 0,
        granted_at_utc TEXT NOT NULL, granted_at_jalali TEXT NOT NULL,
        expires_at_utc TEXT, expires_at_jalali TEXT,
        FOREIGN KEY(user_id) REFERENCES users(user_id),
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id),
        FOREIGN KEY(order_id) REFERENCES orders(order_id),
        UNIQUE(user_id, route_id)
      );

      CREATE TABLE download_events (
        download_id TEXT PRIMARY KEY, entitlement_id TEXT NOT NULL,
        user_id TEXT NOT NULL, route_id TEXT NOT NULL,
        downloaded_at_utc TEXT NOT NULL, downloaded_at_jalali TEXT NOT NULL,
        FOREIGN KEY(entitlement_id) REFERENCES download_entitlements(entitlement_id),
        FOREIGN KEY(user_id) REFERENCES users(user_id),
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id)
      );

      CREATE TABLE discount_codes (
        code TEXT PRIMARY KEY, title TEXT, discount_type TEXT NOT NULL DEFAULT 'percent',
        discount_value INTEGER NOT NULL DEFAULT 0, max_uses INTEGER, used_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'draft', valid_from_utc TEXT, valid_from_jalali TEXT,
        valid_to_utc TEXT, valid_to_jalali TEXT
      );

      CREATE TABLE route_owners (
        route_id TEXT NOT NULL, owner_user_id TEXT NOT NULL,
        ownership_role TEXT NOT NULL DEFAULT 'owner', PRIMARY KEY(route_id, owner_user_id),
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id),
        FOREIGN KEY(owner_user_id) REFERENCES users(user_id)
      );

      CREATE TABLE route_revenue_shares (
        route_id TEXT PRIMARY KEY, owner_percent REAL NOT NULL DEFAULT 0,
        admin_percent REAL NOT NULL DEFAULT 100,
        FOREIGN KEY(route_id) REFERENCES gpx_routes(route_id)
      );

      CREATE TABLE education_categories (
        category_id TEXT PRIMARY KEY, title TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE education_contents (
        content_id TEXT PRIMARY KEY, category_id TEXT NOT NULL, title TEXT NOT NULL,
        body TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
        publication_status TEXT NOT NULL DEFAULT 'published',
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL, updated_at_jalali TEXT NOT NULL,
        FOREIGN KEY(category_id) REFERENCES education_categories(category_id)
      );

      CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT);

      CREATE TABLE schema_migrations (
        migration_id TEXT PRIMARY KEY,
        from_schema INTEGER NOT NULL, to_schema INTEGER NOT NULL,
        applied_at_utc TEXT NOT NULL, applied_at_jalali TEXT NOT NULL
      );

      CREATE TABLE data_migrations (
        migration_id TEXT PRIMARY KEY,
        source_label TEXT NOT NULL,
        applied_at_utc TEXT NOT NULL,
        changed_fields INTEGER NOT NULL DEFAULT 0,
        inserted_routes INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE backup_history (
        backup_id TEXT PRIMARY KEY,
        backup_type TEXT NOT NULL, file_name TEXT,
        status TEXT NOT NULL,
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL
      );

      CREATE TABLE sync_outbox (
        outbox_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        operation TEXT NOT NULL, payload_json TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at_utc TEXT NOT NULL, created_at_jalali TEXT NOT NULL,
        synced_at_utc TEXT
      );
      CREATE INDEX sync_outbox_pending ON sync_outbox(sync_status, outbox_id);

      CREATE VIEW province_stats AS
      SELECT province, COUNT(*) AS total_records,
        SUM(CASE WHEN elevation IS NOT NULL THEN 1 ELSE 0 END) AS elevation_count,
        SUM(CASE WHEN county IS NOT NULL AND TRIM(county)<>'' THEN 1 ELSE 0 END) AS county_count,
        SUM(CASE WHEN latitude IS NOT NULL AND longitude IS NOT NULL THEN 1 ELSE 0 END) AS coordinate_count,
        SUM(CASE WHEN trailhead_elevation_m IS NOT NULL THEN 1 ELSE 0 END) AS trailhead_elevation_count,
        SUM(CASE WHEN elevation_gain_m IS NOT NULL THEN 1 ELSE 0 END) AS elevation_gain_count,
        SUM(CASE WHEN route_length_km IS NOT NULL THEN 1 ELSE 0 END) AS route_length_count,
        SUM(CASE WHEN route IS NOT NULL AND TRIM(route)<>'' THEN 1 ELSE 0 END) AS route_count_filled,
        SUM(CASE WHEN trailhead IS NOT NULL AND TRIM(trailhead)<>'' THEN 1 ELSE 0 END) AS trailhead_count
      FROM peaks WHERE is_deleted=0 GROUP BY province;
    ''')


def build(source: Path, target: Path, database_version: str):
    data = read_registry(source)
    if not data:
        raise SystemExit('Registry sheet is empty')
    headers = [clean(v) for v in data[0]]
    idx = {name: i for i, name in enumerate(headers) if name}
    required = [
        'شناسه کاندید','استان','نام اصلی موقت','ارتفاع منتخب (متر)','شهرستان',
        'عرض جغرافیایی','طول جغرافیایی','مسیر اصلی صعود','نقطه شروع مسیر',
        'ارتفاع نقطه شروع (متر)','اختلاف ارتفاع (متر)','طول مسیر (کیلومتر)','تعداد مسیرها'
    ]
    missing = [name for name in required if name not in idx]
    if missing:
        raise SystemExit(f'Missing required registry columns: {missing}')

    def get(row, header):
        i = idx.get(header)
        return row[i] if i is not None and i < len(row) else None

    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()
    db = sqlite3.connect(target)
    db.execute('PRAGMA foreign_keys=ON')
    create_schema(db)
    now_utc, now_jalali = timestamp_pair()

    peak_sql = '''INSERT INTO peaks (
      id,province,name,aliases,elevation,map_elevation,reported_elevations,source_occurrence_count,
      source,raw_text_sample,source_url,status,county,district,latitude,longitude,
      coordinate_source,route,trailhead,trailhead_elevation_m,elevation_gain_m,
      route_length_km,ascent_time,roundtrip_time,difficulty,best_season,
      guide_required,route_status,local_alias,route_count,mountain_range,description,
      data_flags,data_quality_status,search_text,created_at_utc,created_at_jalali,updated_at_utc,updated_at_jalali
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'''

    source_count = 0
    inserted = 0
    route_scaffolds = 0
    exclusions = 0
    for row in data[1:]:
        id_ = clean(get(row, 'شناسه کاندید'))
        province = clean(get(row, 'استان'))
        name = clean(get(row, 'نام اصلی موقت'))
        if not id_ or not province or not name:
            continue
        source_count += 1
        id_ = str(id_)
        if id_ in EXCLUDED_APP_RECORDS:
            db.execute(
                'INSERT INTO source_exclusions VALUES (?,?,?,?,?,?)',
                (id_, str(name), str(province), EXCLUDED_APP_RECORDS[id_], now_utc, now_jalali),
            )
            exclusions += 1
            continue

        original_province = str(province)
        province = PROVINCE_OVERRIDES.get(id_, original_province)
        aliases = clean(get(row, 'نام‌های مرتبط/احتمالی'))
        county = clean(get(row, 'شهرستان'))
        local_alias = clean(get(row, 'نام محلی / نام مستعار'))
        status = clean(get(row, 'وضعیت اعتبارسنجی'))
        if province != original_province:
            resolution = f'APP-PROVINCE-RESOLVED: {original_province} → {province}'
            status = f'{status} | {resolution}' if status else resolution
        search_text = normalize(' '.join(str(v) for v in (name, aliases, local_alias, province, county) if clean(v) is not None))
        route_count = to_int(get(row, 'تعداد مسیرها')) or 0
        route_name = clean(get(row, 'مسیر اصلی صعود'))
        elevation = to_int(get(row, 'ارتفاع قله (تابلو)')) or to_int(get(row, 'ارتفاع منتخب (متر)'))
        map_elevation = to_int(get(row, 'ارتفاع قله (Map)')) or explicit_map_elevation(get(row, 'ارتفاع‌های گزارش‌شده'))
        latitude = to_float(get(row, 'عرض جغرافیایی'))
        longitude = to_float(get(row, 'طول جغرافیایی'))
        mountain_range = clean(get(row, 'رشته\u200cکوه')) or explicit_mountain_range(id_, get(row, 'بخش/دهستان'), status)
        description = clean(get(row, 'توضیحات'))
        flags = []
        if latitude is None or longitude is None:
            flags.append('missing_coordinates')
        if mountain_range is None:
            flags.append('missing_mountain_range')
        if map_elevation is None:
            flags.append('missing_map_elevation')
        if elevation is None:
            flags.append('missing_summit_sign_elevation')
        status_upper = (str(status) if status else '').upper()
        if any(marker in status_upper for marker in ('AMBIG', 'UNRESOLVED', 'P4-', 'P3 FEATURE', 'AWAITING')):
            flags.append('needs_manual_review')
        data_flags = ','.join(flags) if flags else None
        data_quality_status = 'needs_review' if 'needs_manual_review' in flags else ('complete' if not flags else 'incomplete')
        values = (
            id_, str(province), str(name), aliases, elevation, map_elevation,
            clean(get(row, 'ارتفاع‌های گزارش‌شده')),
            to_int(get(row, 'تعداد رخداد در منبع')), clean(get(row, 'کدهای منبع')),
            clean(get(row, 'نمونه متن خام')), clean(get(row, 'لینک منبع')),
            status, county, clean(get(row, 'بخش/دهستان')),
            latitude, longitude, clean(get(row, 'منبع مختصات')), route_name,
            clean(get(row, 'نقطه شروع مسیر')), to_int(get(row, 'ارتفاع نقطه شروع (متر)')),
            to_int(get(row, 'ارتفاع‌گیری مسیر/GPX (متر)')) or to_int(get(row, 'اختلاف ارتفاع (متر)')),
            to_float(get(row, 'طول مسیر (کیلومتر)')),
            clean(get(row, 'زمان صعود')), clean(get(row, 'زمان رفت‌وبرگشت')),
            clean(get(row, 'درجه سختی')), clean(get(row, 'بهترین فصل صعود')),
            clean(get(row, 'نیاز به راهنما')), clean(get(row, 'وضعیت مسیر')), local_alias,
            route_count, mountain_range, description, data_flags, data_quality_status, search_text,
            now_utc, now_jalali, now_utc, now_jalali,
        )
        db.execute(peak_sql, values)
        inserted += 1

        if route_name or route_count > 0:
            route_id = f'R-{id_.removeprefix("NPC-")}-01'
            scaffold_name = str(route_name) if route_name else f'مسیر {name}'
            trail_lat = to_float(get(row,'عرض جغرافیایی شروع پاکوب'))
            trail_lon = to_float(get(row,'طول جغرافیایی شروع پاکوب'))
            route_gain = to_int(get(row,'ارتفاع‌گیری مسیر/GPX (متر)')) or to_int(get(row,'اختلاف ارتفاع (متر)'))
            route_flags = ['missing_gpx_file']
            if trail_lat is None or trail_lon is None:
                route_flags.insert(0, 'missing_trailhead_coordinates')
            db.execute('''INSERT INTO gpx_routes (
                route_id,peak_id,name,route_length_km,elevation_gain_m,trailhead,
                trailhead_latitude,trailhead_longitude,trailhead_elevation_m,
                source_owner,source_url,price_irr,currency,
                publication_status,download_count,route_count_hint,difficulty,
                estimated_duration,best_season,route_type,data_flags,version,is_deleted,
                created_at_utc,created_at_jalali,updated_at_utc,updated_at_jalali
              ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', (
                route_id,id_,scaffold_name,to_float(get(row,'طول مسیر (کیلومتر)')),
                route_gain,clean(get(row,'نقطه شروع مسیر')),trail_lat,trail_lon,
                to_int(get(row,'ارتفاع نقطه شروع (متر)')),clean(get(row,'کدهای منبع')),
                clean(get(row,'لینک منبع')),0,'IRR','draft',0,max(route_count,1),
                clean(get(row,'درجه سختی')),clean(get(row,'زمان رفت‌وبرگشت')) or clean(get(row,'زمان صعود')),
                clean(get(row,'بهترین فصل صعود')),'ascent',','.join(route_flags),1,0,
                now_utc,now_jalali,now_utc,now_jalali,
            ))
            db.execute('INSERT INTO route_revenue_shares(route_id,owner_percent,admin_percent) VALUES (?,?,?)',
                       (route_id, 0, 100))
            route_scaffolds += 1

    education = load_education_pack()
    for category in education['categories']:
        db.execute(
            'INSERT INTO education_categories(category_id,title,sort_order,is_active) VALUES (?,?,?,1)',
            (category['category_id'], category['title'], int(category['sort_order'])),
        )
    for article in education['contents']:
        db.execute('''INSERT INTO education_contents(
            content_id,category_id,title,body,sort_order,publication_status,
            created_at_utc,created_at_jalali,updated_at_utc,updated_at_jalali
          ) VALUES (?,?,?,?,?,?,?,?,?,?)''',
                   (article['content_id'], article['category_id'], article['title'], article['body'],
                    int(article['sort_order']), article.get('publication_status', 'published'),
                    now_utc, now_jalali, now_utc, now_jalali))

    placeholders = ','.join('?' for _ in OFFICIAL_PROVINCES)
    official_records = db.execute(
        f'SELECT COUNT(*) FROM peaks WHERE province IN ({placeholders})', OFFICIAL_PROVINCES
    ).fetchone()[0]
    label_count = db.execute('SELECT COUNT(DISTINCT province) FROM peaks').fetchone()[0]
    source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    metadata = {
        'database_version': database_version,
        'database_source_file': source.name,
        'database_source_sha256': source_sha,
        'schema_version': SCHEMA_VERSION,
        'dataset_revision': DATASET_REVISION,
        'source_record_count': str(source_count),
        'record_count': str(inserted),
        'controlled_exclusion_count': str(exclusions),
        'route_scaffold_count': str(route_scaffolds),
        'official_province_count': '31',
        'province_label_count': str(label_count),
        'official_province_record_count': str(official_records),
        'cross_province_or_ambiguous_record_count': str(inserted - official_records),
        'generated_at_utc': now_utc,
        'generated_at_jalali': now_jalali,
        'education_revision': education['revision'],
        'education_content_count': str(len(education['contents'])),
    }
    db.executemany('INSERT INTO metadata(key,value) VALUES (?,?)', metadata.items())
    db.execute(
        'INSERT INTO schema_migrations(migration_id,from_schema,to_schema,applied_at_utc,applied_at_jalali) VALUES (?,?,?,?,?)',
        (f'S0-S{SCHEMA_VERSION}-bundle', 0, int(SCHEMA_VERSION), now_utc, now_jalali),
    )
    db.execute(
        'INSERT INTO data_migrations(migration_id,source_label,applied_at_utc,changed_fields,inserted_routes) VALUES (?,?,?,?,?)',
        ('EDU-V1-20260912', education['revision'], now_utc, len(education['contents']), 0),
    )
    db.commit()
    fk = db.execute('PRAGMA foreign_key_check').fetchall()
    integrity = db.execute('PRAGMA integrity_check').fetchone()[0]
    db.close()
    if integrity != 'ok' or fk:
        raise SystemExit(f'Generated database failed QA: integrity={integrity}, fk={fk[:5]}')
    print(f'Created {target} | source={source_count} publishable={inserted} exclusions={exclusions} routes={route_scaffolds} schema={SCHEMA_VERSION}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('target', type=Path)
    parser.add_argument('--database-version', default='DPD v3.88')
    args = parser.parse_args()
    build(args.source, args.target, args.database_version)


if __name__ == '__main__':
    main()
