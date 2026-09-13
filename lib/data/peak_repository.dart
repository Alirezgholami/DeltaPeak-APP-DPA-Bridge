import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../app_info.dart';
import '../auth/session_store.dart';
import '../models/audit_entry.dart';
import '../models/database_info.dart';
import '../models/education.dart';
import '../models/gpx_route.dart';
import '../models/peak.dart';
import '../models/province_stat.dart';
import '../models/user_account.dart';
import '../utils/jalali.dart';
import '../utils/persian_normalizer.dart';

class PurchaseResult {
  const PurchaseResult(this.code, this.message);
  final String code;
  final String message;
}

class StoredGpxFile {
  const StoredGpxFile({required this.path, required this.sha256});
  final String path;
  final String sha256;
}

class PeakRepository {
  PeakRepository._();

  static const List<String> officialProvinceOrder = [
    'آذربایجان شرقی', 'آذربایجان غربی', 'اردبیل', 'اصفهان', 'البرز', 'ایلام',
    'بوشهر', 'تهران', 'چهارمحال و بختیاری', 'خراسان جنوبی', 'خراسان رضوی',
    'خراسان شمالی', 'خوزستان', 'زنجان', 'سمنان', 'سیستان و بلوچستان', 'فارس',
    'قزوین', 'قم', 'کردستان', 'کرمان', 'کرمانشاه', 'کهگیلویه و بویراحمد',
    'گلستان', 'گیلان', 'لرستان', 'مازندران', 'مرکزی', 'هرمزگان', 'همدان', 'یزد',
  ];

  static final instance = PeakRepository._();
  late Database _db;
  late String _dbPath;

  String get databasePath => _dbPath;

  Future<void> initialize() async {
    final docs = await getApplicationDocumentsDirectory();
    _dbPath = p.join(docs.path, 'dpa_peaks.db');

    if (!await File(_dbPath).exists()) {
      final candidates = [
        p.join(docs.path, 'dpa_peaks_v388_s3.db'),
        p.join(docs.path, 'dpa_peaks_v388_s2.db'),
        p.join(docs.path, 'dpa_peaks_v382.db'),
      ];
      String? previous;
      for (final candidate in candidates) {
        if (await File(candidate).exists()) {
          previous = candidate;
          break;
        }
      }
      if (previous != null) {
        await File(previous).copy(_dbPath);
      } else {
        await _copyBundledDatabase(_dbPath);
      }
    }

    await _createPreMigrationSnapshotIfNeeded();
    _db = await openDatabase(_dbPath);
    await _migrateSchema();
    await _mergeBundledReferenceDataIfNeeded();
    await _ensureEducationPack();
    await _syncMountainRangeMaster();
    await _assertIntegrity();
  }

  Future<void> _copyBundledDatabase(String path) async {
    final bytes = await rootBundle.load('assets/peaks.db');
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  Future<int> _schemaVersionFromFile(String path) async {
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true);
      final rows = await db.query('metadata', columns: ['value'], where: "key='schema_version'", limit: 1);
      return rows.isEmpty ? 0 : int.tryParse('${rows.first['value']}') ?? 0;
    } catch (_) {
      return 0;
    } finally {
      if (db != null) await db.close();
    }
  }

  Future<void> _createPreMigrationSnapshotIfNeeded() async {
    final version = await _schemaVersionFromFile(_dbPath);
    if (version >= int.parse(AppInfo.expectedSchemaVersion)) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'safety_snapshots'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    await File(_dbPath).copy(p.join(dir.path, 'pre_migration_s${version}_$stamp.db'));
  }

  Future<void> _migrateSchema() async {
    await _db.transaction((txn) async {
      await txn.execute('''CREATE TABLE IF NOT EXISTS schema_migrations (
        migration_id TEXT PRIMARY KEY,
        from_schema INTEGER NOT NULL,
        to_schema INTEGER NOT NULL,
        applied_at_utc TEXT NOT NULL,
        applied_at_jalali TEXT NOT NULL
      )''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS data_migrations (
        migration_id TEXT PRIMARY KEY,
        source_label TEXT NOT NULL,
        applied_at_utc TEXT NOT NULL,
        changed_fields INTEGER NOT NULL DEFAULT 0,
        inserted_routes INTEGER NOT NULL DEFAULT 0
      )''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS backup_history (
        backup_id TEXT PRIMARY KEY,
        backup_type TEXT NOT NULL,
        file_name TEXT,
        status TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        created_at_jalali TEXT NOT NULL
      )''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_outbox (
        outbox_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at_utc TEXT NOT NULL,
        created_at_jalali TEXT NOT NULL,
        synced_at_utc TEXT
      )''');

      await txn.execute('''CREATE TABLE IF NOT EXISTS mountain_ranges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL UNIQUE,
        usage_count INTEGER NOT NULL DEFAULT 0,
        created_at_utc TEXT NOT NULL,
        created_at_jalali TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        updated_at_jalali TEXT NOT NULL
      )''');

      final peakColumns = await _columnNames(txn, 'peaks');
      if (!peakColumns.contains('map_elevation')) {
        await txn.execute('ALTER TABLE peaks ADD COLUMN map_elevation INTEGER');
      }
      if (!peakColumns.contains('data_flags')) {
        await txn.execute('ALTER TABLE peaks ADD COLUMN data_flags TEXT');
      }
      if (!peakColumns.contains('data_quality_status')) {
        await txn.execute("ALTER TABLE peaks ADD COLUMN data_quality_status TEXT NOT NULL DEFAULT 'incomplete'");
      }

      if (!peakColumns.contains('mountain_range_id')) {
        await txn.execute('ALTER TABLE peaks ADD COLUMN mountain_range_id INTEGER');
      }

      final routeColumns = await _columnNames(txn, 'gpx_routes');
      if (!routeColumns.contains('data_flags')) {
        await txn.execute('ALTER TABLE gpx_routes ADD COLUMN data_flags TEXT');
      }

      final userColumns = await _columnNames(txn, 'users');
      if (!userColumns.contains('role')) {
        await txn.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'");
      }
      if (!userColumns.contains('last_login_at_utc')) {
        await txn.execute('ALTER TABLE users ADD COLUMN last_login_at_utc TEXT');
      }
      if (!userColumns.contains('last_login_at_jalali')) {
        await txn.execute('ALTER TABLE users ADD COLUMN last_login_at_jalali TEXT');
      }
      if (!userColumns.contains('last_activity_at_utc')) {
        await txn.execute('ALTER TABLE users ADD COLUMN last_activity_at_utc TEXT');
      }
      if (!userColumns.contains('last_activity_at_jalali')) {
        await txn.execute('ALTER TABLE users ADD COLUMN last_activity_at_jalali TEXT');
      }

      await txn.execute('CREATE INDEX IF NOT EXISTS peaks_quality ON peaks(data_quality_status, is_deleted)');
      await txn.execute('CREATE INDEX IF NOT EXISTS routes_sha256 ON gpx_routes(file_sha256)');
      await txn.execute('CREATE INDEX IF NOT EXISTS peaks_mountain_range_id ON peaks(mountain_range_id)');
      await txn.execute('CREATE INDEX IF NOT EXISTS mountain_ranges_usage ON mountain_ranges(usage_count DESC, name)');

      await _refreshDataFlags(txn);
      final ts = _timestamps();
      final current = await txn.query('metadata', columns: ['value'], where: "key='schema_version'", limit: 1);
      final from = current.isEmpty ? 0 : int.tryParse('${current.first['value']}') ?? 0;
      await txn.insert('metadata', {'key': 'schema_version', 'value': AppInfo.expectedSchemaVersion}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('metadata', {'key': 'dataset_revision', 'value': AppInfo.expectedDatasetRevision}, conflictAlgorithm: ConflictAlgorithm.replace);
      if (from < int.parse(AppInfo.expectedSchemaVersion)) {
        await txn.insert('schema_migrations', {
          'migration_id': 'S$from-S${AppInfo.expectedSchemaVersion}-${ts.$1}',
          'from_schema': from,
          'to_schema': int.parse(AppInfo.expectedSchemaVersion),
          'applied_at_utc': ts.$1,
          'applied_at_jalali': ts.$2,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  static const String _referenceMergeId = 'REF-V390-B09';

  static const List<String> _referencePeakFields = [
    'aliases', 'elevation', 'map_elevation', 'reported_elevations',
    'source_occurrence_count', 'source', 'raw_text_sample', 'source_url', 'status',
    'county', 'district', 'latitude', 'longitude', 'coordinate_source', 'route',
    'trailhead', 'trailhead_elevation_m', 'elevation_gain_m', 'route_length_km',
    'ascent_time', 'roundtrip_time', 'difficulty', 'best_season', 'guide_required',
    'route_status', 'local_alias', 'mountain_range', 'description',
  ];

  static const List<String> _referenceRouteFields = [
    'name', 'gpx_file_path', 'route_length_km', 'elevation_gain_m', 'trailhead',
    'trailhead_latitude', 'trailhead_longitude', 'trailhead_elevation_m',
    'source_owner', 'source_url', 'route_count_hint', 'difficulty',
    'estimated_duration', 'best_season', 'route_type', 'file_sha256', 'data_flags',
  ];

  bool _isEmptyReferenceValue(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);

  Future<void> _mergeBundledReferenceDataIfNeeded() async {
    final marker = await _db.query(
      'data_migrations',
      columns: ['migration_id'],
      where: 'migration_id=?',
      whereArgs: const [_referenceMergeId],
      limit: 1,
    );
    if (marker.isNotEmpty) return;

    final docs = await getApplicationDocumentsDirectory();
    final referencePath = p.join(docs.path, 'dpa_reference_v053.db');
    Database? referenceDb;
    try {
      await _copyBundledDatabase(referencePath);
      referenceDb = await openDatabase(referencePath, readOnly: true);

      final referencePeaks = await referenceDb.query('peaks');
      final referenceRoutes = await referenceDb.query('gpx_routes');
      final referenceMetaRows = await referenceDb.query('metadata', columns: ['key', 'value']);
      final referenceMeta = <String, String>{
        for (final row in referenceMetaRows) '${row['key']}': '${row['value']}',
      };

      final protectedPeakRows = await _db.query(
        'audit_log',
        columns: ['entity_id', 'field_name'],
        where: "entity_type='peak' AND field_name IS NOT NULL",
      );
      final protectedPeakFields = <String>{
        for (final row in protectedPeakRows)
          '${row['entity_id']}|${row['field_name']}',
      };
      final protectedRouteRows = await _db.query(
        'audit_log',
        columns: ['entity_id'],
        where: "entity_type='route' AND action IN ('add','update')",
      );
      final protectedRouteIds =
          protectedRouteRows.map((row) => '${row['entity_id']}').toSet();

      var changedFields = 0;
      var insertedRoutes = 0;
      await _db.transaction((txn) async {
        for (final ref in referencePeaks) {
          final id = '${ref['id']}';
          final currentRows =
              await txn.query('peaks', where: 'id=?', whereArgs: [id], limit: 1);
          if (currentRows.isEmpty) {
            await txn.insert(
              'peaks',
              Map<String, Object?>.from(ref),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            continue;
          }
          final current = currentRows.first;
          final changes = <String, Object?>{};
          for (final field in _referencePeakFields) {
            if (protectedPeakFields.contains('$id|$field')) continue;
            final localValue = current[field];
            final referenceValue = ref[field];
            if (_isEmptyReferenceValue(localValue) &&
                !_isEmptyReferenceValue(referenceValue)) {
              changes[field] = referenceValue;
            }
          }
          if (changes.isNotEmpty) {
            await txn.update('peaks', changes, where: 'id=?', whereArgs: [id]);
            changedFields += changes.length;
          }
        }

        for (final ref in referenceRoutes) {
          final routeId = '${ref['route_id']}';
          final currentRows = await txn.query(
            'gpx_routes',
            where: 'route_id=?',
            whereArgs: [routeId],
            limit: 1,
          );
          if (currentRows.isEmpty) {
            await txn.insert(
              'gpx_routes',
              Map<String, Object?>.from(ref),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            insertedRoutes++;
            continue;
          }
          if (protectedRouteIds.contains(routeId)) continue;
          final current = currentRows.first;
          final changes = <String, Object?>{};
          for (final field in _referenceRouteFields) {
            final localValue = current[field];
            final referenceValue = ref[field];
            if (_isEmptyReferenceValue(localValue) &&
                !_isEmptyReferenceValue(referenceValue)) {
              changes[field] = referenceValue;
            }
          }
          if (changes.isNotEmpty) {
            await txn.update(
              'gpx_routes',
              changes,
              where: 'route_id=?',
              whereArgs: [routeId],
            );
            changedFields += changes.length;
          }
        }

        await txn.execute('''
          UPDATE peaks
          SET route_count=(
            SELECT COUNT(*) FROM gpx_routes r
            WHERE r.peak_id=peaks.id AND r.is_deleted=0
          )
        ''');
        await txn.execute('''
          UPDATE gpx_routes
          SET data_flags = NULLIF(
            TRIM(
              REPLACE(
                REPLACE(
                  REPLACE(
                    COALESCE(data_flags,''),
                    'missing_trailhead_coordinates,',
                    ''
                  ),
                  ',missing_trailhead_coordinates',
                  ''
                ),
                'missing_trailhead_coordinates',
                ''
              ),
              ','
            ),
            ''
          )
          WHERE trailhead_latitude IS NOT NULL
            AND trailhead_longitude IS NOT NULL
        ''');
        await _refreshDataFlags(txn);

        for (final key in const [
          'database_version',
          'dataset_revision',
          'database_source_file',
          'database_source_sha256',
          'source_record_count',
          'record_count',
          'controlled_exclusion_count',
          'official_province_count',
          'official_province_record_count',
          'province_label_count',
          'enrichment_patch_id',
          'enrichment_patch_sha256',
          'route_scaffold_count',
          'generated_at_utc',
          'generated_at_jalali',
          'enriched_at_utc',
        ]) {
          final value = referenceMeta[key];
          if (value != null) {
            await txn.insert(
              'metadata',
              {'key': key, 'value': value},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        await txn.insert(
          'metadata',
          {'key': 'schema_version', 'value': AppInfo.expectedSchemaVersion},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final ts = _timestamps();
        await txn.insert(
          'data_migrations',
          {
            'migration_id': _referenceMergeId,
            'source_label': referenceMeta['database_version'] ??
                AppInfo.expectedDatabaseVersion,
            'applied_at_utc': ts.$1,
            'changed_fields': changedFields,
            'inserted_routes': insertedRoutes,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      });
    } finally {
      if (referenceDb != null) await referenceDb.close();
      final referenceFile = File(referencePath);
      if (await referenceFile.exists()) await referenceFile.delete();
    }
  }

  static const String _educationMigrationId = 'EDU-V1-20260912-R2';

  Future<void> _ensureEducationPack() async {
    final marker = await _db.query(
      'data_migrations',
      columns: ['migration_id'],
      where: 'migration_id=?',
      whereArgs: const [_educationMigrationId],
      limit: 1,
    );
    if (marker.isNotEmpty) return;

    final raw = await rootBundle.loadString('assets/education_v1.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['revision'] != 'edu-v1-20260912') {
      throw StateError('Invalid DPA education pack');
    }
    final categories = (decoded['categories'] as List<dynamic>? ?? const []);
    final contents = (decoded['contents'] as List<dynamic>? ?? const []);
    if (categories.length != 6 || contents.length != 42) {
      throw StateError('Incomplete DPA education pack');
    }

    final ts = _timestamps();
    await _db.transaction((txn) async {
      // Remove only the six legacy placeholder articles from v0.2.x-v0.5.5.
      // Unknown/custom education rows are intentionally preserved.
      await txn.delete(
        'education_contents',
        where: 'content_id IN (?,?,?,?,?,?)',
        whereArgs: const [
          'EDU-ART-01', 'EDU-ART-02', 'EDU-ART-03',
          'EDU-ART-04', 'EDU-ART-05', 'EDU-ART-06',
        ],
      );

      for (final rawCategory in categories) {
        final category = Map<String, dynamic>.from(rawCategory as Map);
        await txn.insert(
          'education_categories',
          {
            'category_id': category['category_id'],
            'title': category['title'],
            'sort_order': category['sort_order'],
            'is_active': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final rawArticle in contents) {
        final article = Map<String, dynamic>.from(rawArticle as Map);
        await txn.insert(
          'education_contents',
          {
            'content_id': article['content_id'],
            'category_id': article['category_id'],
            'title': article['title'],
            'body': article['body'],
            'sort_order': article['sort_order'],
            'publication_status': article['publication_status'] ?? 'published',
            'created_at_utc': ts.$1,
            'created_at_jalali': ts.$2,
            'updated_at_utc': ts.$1,
            'updated_at_jalali': ts.$2,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert(
        'metadata',
        {'key': 'education_revision', 'value': '${decoded['revision']}'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'metadata',
        {'key': 'education_content_count', 'value': '${contents.length}'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'data_migrations',
        {
          'migration_id': _educationMigrationId,
          'source_label': '${decoded['revision']}',
          'applied_at_utc': ts.$1,
          'changed_fields': contents.length,
          'inserted_routes': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<Set<String>> _columnNames(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((e) => '${e['name']}').toSet();
  }

  Future<(int, String)?> _ensureMountainRange(
    DatabaseExecutor db,
    String? rawValue,
  ) async {
    final canonical = PersianNormalizer.normalizeText(rawValue);
    if (canonical.isEmpty || PersianNormalizer.isMissingPlaceholder(canonical)) return null;
    final normalized = PersianNormalizer.normalizeSearch(canonical);
    final existing = await db.query(
      'mountain_ranges',
      columns: ['id', 'name'],
      where: 'normalized_name=?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = (existing.first['id'] as num).toInt();
      final storedName = "${existing.first['name']}";
      if (storedName != canonical) {
        final ts = _timestamps();
        await db.update(
          'mountain_ranges',
          {'name': canonical, 'updated_at_utc': ts.$1, 'updated_at_jalali': ts.$2},
          where: 'id=?',
          whereArgs: [id],
        );
      }
      return (id, canonical);
    }

    final ts = _timestamps();
    final id = await db.insert('mountain_ranges', {
      'name': canonical,
      'normalized_name': normalized,
      'usage_count': 0,
      'created_at_utc': ts.$1,
      'created_at_jalali': ts.$2,
      'updated_at_utc': ts.$1,
      'updated_at_jalali': ts.$2,
    });
    return (id, canonical);
  }

  Future<void> _refreshMountainRangeUsage(DatabaseExecutor db) async {
    await db.execute(
      'UPDATE mountain_ranges SET usage_count=('
      'SELECT COUNT(*) FROM peaks p '
      'WHERE p.is_deleted=0 AND p.mountain_range_id=mountain_ranges.id'
      ')',
    );
  }

  Future<void> _syncMountainRangeMaster() async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'peaks',
        columns: [
          'id', 'name', 'aliases', 'local_alias', 'province', 'county',
          'mountain_range', 'mountain_range_id', 'search_text',
        ],
      );
      for (final row in rows) {
        final updates = <String, Object?>{};
        final range = await _ensureMountainRange(txn, row['mountain_range']?.toString());
        if (range == null) {
          if (row['mountain_range_id'] != null) updates['mountain_range_id'] = null;
        } else {
          if (row['mountain_range_id'] != range.$1) updates['mountain_range_id'] = range.$1;
          if (row['mountain_range']?.toString() != range.$2) updates['mountain_range'] = range.$2;
        }

        // Rebuild the search key once during migration so older Arabic/Persian
        // spelling variants (ي/ی, ك/ک, etc.) are searchable with the new input
        // normalizer without rewriting the source/reference fields themselves.
        final searchSource = Map<String, Object?>.from(row);
        if (updates.containsKey('mountain_range')) {
          searchSource['mountain_range'] = updates['mountain_range'];
        }
        final searchText = _peakSearchTextFromData(searchSource);
        if (row['search_text']?.toString() != searchText) updates['search_text'] = searchText;

        if (updates.isNotEmpty) {
          await txn.update('peaks', updates, where: 'id=?', whereArgs: [row['id']]);
        }
      }
      await _refreshMountainRangeUsage(txn);
    });
  }

  Future<List<String>> mountainRangeNames() async {
    final rows = await _db.query(
      'mountain_ranges',
      columns: ['name'],
      orderBy: 'usage_count DESC, name COLLATE NOCASE',
    );
    return rows.map((row) => "${row['name']}").toList(growable: false);
  }

  Future<void> _refreshDataFlags(DatabaseExecutor db) async {
    final rows = await db.query(
      'peaks',
      columns: ['id', 'latitude', 'longitude', 'mountain_range', 'map_elevation', 'elevation', 'status'],
    );
    final batch = db.batch();
    for (final row in rows) {
      final flags = <String>[];
      if (row['latitude'] == null || row['longitude'] == null) flags.add('missing_coordinates');
      if (PersianNormalizer.isMissingPlaceholder(row['mountain_range'])) flags.add('missing_mountain_range');
      final mapElevation = (row['map_elevation'] as num?)?.toDouble();
      if (mapElevation == null || mapElevation <= 0) flags.add('missing_map_elevation');
      final summitElevation = (row['elevation'] as num?)?.toDouble();
      if (summitElevation == null || summitElevation <= 0) flags.add('missing_summit_sign_elevation');
      final status = (row['status']?.toString() ?? '').toUpperCase();
      final uncertain = status.contains('AMBIG') || status.contains('UNRESOLVED') || status.contains('P4-') || status.contains('P3 FEATURE') || status.contains('AWAITING');
      if (uncertain) flags.add('needs_manual_review');
      final quality = flags.isEmpty ? 'complete' : (uncertain ? 'needs_review' : 'incomplete');
      batch.update('peaks', {
        'data_flags': flags.isEmpty ? null : flags.join(','),
        'data_quality_status': quality,
      }, where: 'id=?', whereArgs: [row['id']]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _assertIntegrity() async {
    final result = await _db.rawQuery('PRAGMA integrity_check');
    final value = result.isEmpty ? '' : result.first.values.first?.toString();
    if (value != 'ok') throw StateError('Database integrity check failed: $value');
  }

  Future<DatabaseInfo> databaseInfo() async {
    final rows = await _db.query('metadata', columns: ['key', 'value']);
    return DatabaseInfo(values: {
      for (final row in rows) row['key'] as String: row['value'] as String,
    });
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('app_settings', columns: ['value'], where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('app_settings', where: 'key=?', whereArgs: [key]);
      return;
    }
    await _db.insert('app_settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> provinces() async {
    final rows = await _db.rawQuery('SELECT DISTINCT province FROM peaks WHERE is_deleted=0');
    final present = rows.map((e) => e['province'] as String).toSet();
    return officialProvinceOrder.where(present.contains).toList();
  }

  (String, List<Object?>) _searchWhere({
    String query = '',
    String? province,
    String? qualityFilter,
    bool favoritesOnly = false,
    bool? hasCoordinates,
    bool? hasGpx,
  }) {
    final normalized = _normalize(query);
    final clauses = <String>['p.is_deleted=0'];
    final args = <Object?>[];
    if (normalized.isNotEmpty) {
      clauses.add('(p.search_text LIKE ? OR p.id LIKE ?)');
      args..add('%$normalized%')..add('%$normalized%');
    }
    if (province != null) {
      clauses.add('p.province=?');
      args.add(province);
    }
    if (qualityFilter != null && qualityFilter.isNotEmpty) {
      clauses.add('p.data_quality_status=?');
      args.add(qualityFilter);
    }
    if (favoritesOnly) clauses.add('p.favorite=1');
    if (hasCoordinates == true) clauses.add('p.latitude IS NOT NULL AND p.longitude IS NOT NULL');
    if (hasCoordinates == false) clauses.add('(p.latitude IS NULL OR p.longitude IS NULL)');
    if (hasGpx == true) clauses.add('EXISTS(SELECT 1 FROM gpx_routes r WHERE r.peak_id=p.id AND r.is_deleted=0 AND r.gpx_file_path IS NOT NULL)');
    if (hasGpx == false) clauses.add('NOT EXISTS(SELECT 1 FROM gpx_routes r WHERE r.peak_id=p.id AND r.is_deleted=0 AND r.gpx_file_path IS NOT NULL)');
    return (clauses.join(' AND '), args);
  }

  Future<List<Peak>> search({
    String query = '',
    String? province,
    String? qualityFilter,
    bool favoritesOnly = false,
    bool? hasCoordinates,
    bool? hasGpx,
  }) async {
    final spec = _searchWhere(
      query: query,
      province: province,
      qualityFilter: qualityFilter,
      favoritesOnly: favoritesOnly,
      hasCoordinates: hasCoordinates,
      hasGpx: hasGpx,
    );
    final rows = await _db.rawQuery(
      'SELECT p.* FROM peaks p WHERE ${spec.$1} ORDER BY p.favorite DESC, p.name COLLATE NOCASE',
      spec.$2,
    );
    return rows.map(Peak.fromMap).toList();
  }

  Future<int> countSearch({
    String query = '',
    String? province,
    String? qualityFilter,
    bool favoritesOnly = false,
    bool? hasCoordinates,
    bool? hasGpx,
  }) async {
    final spec = _searchWhere(
      query: query,
      province: province,
      qualityFilter: qualityFilter,
      favoritesOnly: favoritesOnly,
      hasCoordinates: hasCoordinates,
      hasGpx: hasGpx,
    );
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM peaks p WHERE ${spec.$1}', spec.$2);
    return (rows.first['c'] as num).toInt();
  }

  Future<Peak?> getById(String id, {bool includeDeleted = false}) async {
    final rows = await _db.query(
      'peaks',
      where: includeDeleted ? 'id=?' : 'id=? AND is_deleted=0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Peak.fromMap(rows.first);
  }

  Future<void> toggleFavorite(Peak peak) async {
    await _db.update('peaks', {'favorite': peak.favorite ? 0 : 1}, where: 'id=?', whereArgs: [peak.id]);
  }

  (String, String) _timestamps() => (DateTime.now().toUtc().toIso8601String(), JalaliDate.now());

  Future<UserAccount> _requireManager() async {
    final session = SessionStore.instance;
    final user = session.currentUser;
    if (user != null && user.isAdmin) return user;
    if (session.isInternalOwnerMode) {
      return const UserAccount(
        userId: 'internal-owner',
        displayName: 'مالک محلی',
        mobile: 'local',
        status: 'active',
        role: 'owner',
        createdAtJalali: 'internal',
      );
    }
    throw StateError('این عملیات فقط برای Owner یا Admin واردشده مجاز است.');
  }

  String _actor(UserAccount user) => '${user.role}:${user.mobile}';

  static const Set<String> _normalizedPeakTextFields = {
    'province', 'name', 'aliases', 'reported_elevations', 'status', 'county',
    'district', 'coordinate_source', 'route', 'trailhead', 'ascent_time',
    'roundtrip_time', 'difficulty', 'best_season', 'guide_required',
    'route_status', 'local_alias', 'mountain_range', 'description',
  };

  Map<String, Object?> _normalizePeakEditableMap(Map<String, Object?> input) {
    final data = Map<String, Object?>.from(input);
    for (final field in _normalizedPeakTextFields) {
      if (!data.containsKey(field)) continue;
      final raw = data[field];
      if (raw == null) continue;
      final normalized = PersianNormalizer.normalizeText(raw.toString());
      data[field] = normalized.isEmpty ? null : normalized;
    }
    return data;
  }

  ({String? flags, String quality}) _qualityForPeakData(Map<String, Object?> peak) {
    final flags = <String>[];
    if (peak['latitude'] == null || peak['longitude'] == null) flags.add('missing_coordinates');
    if (PersianNormalizer.isMissingPlaceholder(peak['mountain_range'])) flags.add('missing_mountain_range');
    final mapElevation = (peak['map_elevation'] as num?)?.toDouble();
    if (mapElevation == null || mapElevation <= 0) flags.add('missing_map_elevation');
    final summitElevation = (peak['elevation'] as num?)?.toDouble();
    if (summitElevation == null || summitElevation <= 0) flags.add('missing_summit_sign_elevation');
    final status = (peak['status']?.toString() ?? '').toUpperCase();
    final uncertain = status.contains('AMBIG') || status.contains('UNRESOLVED') ||
        status.contains('P4-') || status.contains('P3 FEATURE') || status.contains('AWAITING');
    if (uncertain) flags.add('needs_manual_review');
    return (
      flags: flags.isEmpty ? null : flags.join(','),
      quality: flags.isEmpty ? 'complete' : (uncertain ? 'needs_review' : 'incomplete'),
    );
  }

  String _peakSearchTextFromData(Map<String, Object?> data) =>
      PersianNormalizer.normalizeSearch([
        data['name'], data['aliases'], data['local_alias'], data['province'],
        data['county'], data['mountain_range'],
      ].whereType<Object>().map((e) => e.toString()).join(' '));

  Future<void> updatePeak(Peak peak) async {
    final manager = await _requireManager();
    final currentRows = await _db.query('peaks', where: 'id=?', whereArgs: [peak.id], limit: 1);
    if (currentRows.isEmpty) throw StateError('Peak not found: ${peak.id}');
    final current = currentRows.first;
    final changes = _normalizePeakEditableMap(peak.toEditableMap());
    final province = changes['province']?.toString();
    final name = changes['name']?.toString();
    if (name == null || name.isEmpty) throw StateError('نام قله الزامی است.');
    if (province == null || !officialProvinceOrder.contains(province)) {
      throw StateError('استان انتخاب‌شده معتبر نیست.');
    }
    final ts = _timestamps();

    await _db.transaction((txn) async {
      final range = await _ensureMountainRange(txn, changes['mountain_range']?.toString());
      changes['mountain_range_id'] = range?.$1;
      changes['mountain_range'] = range?.$2;
      final quality = _qualityForPeakData(changes);
      changes['data_flags'] = quality.flags;
      changes['data_quality_status'] = quality.quality;
      changes['search_text'] = _peakSearchTextFromData(changes);
      changes['updated_at_utc'] = ts.$1;
      changes['updated_at_jalali'] = ts.$2;

      for (final entry in changes.entries) {
        if (entry.key.startsWith('updated_at_') || entry.key == 'search_text') continue;
        final before = current[entry.key];
        if (_sameValue(before, entry.value)) continue;
        await _audit(txn, entityType: 'peak', entityId: peak.id, peakId: peak.id,
            action: 'update', field: entry.key, before: before, after: entry.value,
            actor: _actor(manager), ts: ts);
      }
      await txn.update('peaks', changes, where: 'id=?', whereArgs: [peak.id]);
      await _refreshMountainRangeUsage(txn);
      await _enqueueSync(txn, 'peak', peak.id, 'update', changes, ts);
    });
  }

  Future<String> addPeak(Peak peak) async {
    final manager = await _requireManager();
    final ts = _timestamps();
    final id = peak.id.trim().isEmpty ? 'LOCAL-P-${DateTime.now().microsecondsSinceEpoch}' : peak.id;
    final data = _normalizePeakEditableMap(peak.toEditableMap());
    final province = data['province']?.toString();
    final name = data['name']?.toString();
    if (name == null || name.isEmpty) throw StateError('نام قله الزامی است.');
    if (province == null || !officialProvinceOrder.contains(province)) {
      throw StateError('استان انتخاب‌شده معتبر نیست.');
    }

    await _db.transaction((txn) async {
      final range = await _ensureMountainRange(txn, data['mountain_range']?.toString());
      data['mountain_range_id'] = range?.$1;
      data['mountain_range'] = range?.$2;
      final quality = _qualityForPeakData(data);
      data['data_flags'] = quality.flags;
      data['data_quality_status'] = quality.quality;
      data.addAll({
        'id': id,
        'favorite': peak.favorite ? 1 : 0,
        'is_deleted': 0,
        'search_text': _peakSearchTextFromData(data),
        'created_at_utc': ts.$1,
        'created_at_jalali': ts.$2,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      });
      await txn.insert('peaks', data);
      await _refreshMountainRangeUsage(txn);
      await _audit(txn, entityType: 'peak', entityId: id, peakId: id,
          action: 'add', actor: _actor(manager), ts: ts);
      await _enqueueSync(txn, 'peak', id, 'add', data, ts);
    });
    return id;
  }

  Future<void> softDeletePeak(String peakId) async {
    final manager = await _requireManager();
    final ts = _timestamps();
    await _db.transaction((txn) async {
      await txn.update('peaks', {
        'is_deleted': 1,
        'deleted_at_utc': ts.$1,
        'deleted_at_jalali': ts.$2,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      }, where: 'id=?', whereArgs: [peakId]);
      await txn.update('gpx_routes', {
        'is_deleted': 1,
        'deleted_at_utc': ts.$1,
        'deleted_at_jalali': ts.$2,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      }, where: 'peak_id=?', whereArgs: [peakId]);
      await _refreshMountainRangeUsage(txn);
      await _audit(txn, entityType: 'peak', entityId: peakId, peakId: peakId,
          action: 'soft_delete', actor: _actor(manager), ts: ts);
      await _enqueueSync(txn, 'peak', peakId, 'soft_delete', const {}, ts);
    });
  }

  Future<List<Peak>> deletedPeaks() async {
    await _requireManager();
    final rows = await _db.query('peaks', where: 'is_deleted=1', orderBy: 'deleted_at_utc DESC');
    return rows.map(Peak.fromMap).toList();
  }

  Future<void> restorePeak(String peakId) async {
    final manager = await _requireManager();
    final ts = _timestamps();
    await _db.transaction((txn) async {
      await txn.update('peaks', {
        'is_deleted': 0,
        'deleted_at_utc': null,
        'deleted_at_jalali': null,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      }, where: 'id=?', whereArgs: [peakId]);
      await txn.update('gpx_routes', {
        'is_deleted': 0,
        'deleted_at_utc': null,
        'deleted_at_jalali': null,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      }, where: 'peak_id=?', whereArgs: [peakId]);
      await _refreshMountainRangeUsage(txn);
      await _audit(txn, entityType: 'peak', entityId: peakId, peakId: peakId,
          action: 'restore', actor: _actor(manager), ts: ts);
      await _enqueueSync(txn, 'peak', peakId, 'restore', const {}, ts);
    });
  }

  Future<List<GpxRoute>> routesForPeak(String peakId) async {
    final rows = await _db.query('gpx_routes', where: 'peak_id=? AND is_deleted=0', whereArgs: [peakId], orderBy: 'name COLLATE NOCASE');
    return rows.map(GpxRoute.fromMap).toList();
  }

  Future<GpxRoute?> routeById(String routeId) async {
    final rows = await _db.query('gpx_routes', where: 'route_id=? AND is_deleted=0', whereArgs: [routeId], limit: 1);
    return rows.isEmpty ? null : GpxRoute.fromMap(rows.first);
  }

  Future<StoredGpxFile> importGpxFile(String sourcePath, {String? currentRouteId}) async {
    final manager = await _requireManager();
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('فایل GPX پیدا نشد.');
    final bytes = await source.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final duplicate = await _db.query(
      'gpx_routes',
      columns: ['route_id'],
      where: currentRouteId == null
          ? 'file_sha256=? AND is_deleted=0'
          : 'file_sha256=? AND route_id<>? AND is_deleted=0',
      whereArgs: currentRouteId == null ? [digest] : [digest, currentRouteId],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw StateError('این فایل GPX قبلاً برای مسیر ${duplicate.first['route_id']} ثبت شده است.');
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'gpx'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, '$digest.gpx');
    if (!await File(target).exists()) await File(target).writeAsBytes(bytes, flush: true);
    await setSetting('last_gpx_import_actor', _actor(manager));
    return StoredGpxFile(path: target, sha256: digest);
  }

  Future<String> saveRoute(GpxRoute route) async {
    final manager = await _requireManager();
    final ts = _timestamps();
    final routeId = route.routeId.trim().isEmpty ? 'R-LOCAL-${DateTime.now().microsecondsSinceEpoch}' : route.routeId;
    final existing = await _db.query('gpx_routes', where: 'route_id=?', whereArgs: [routeId], limit: 1);
    final normalizedName = PersianNormalizer.normalizeText(route.name);
    if (normalizedName.isEmpty) throw StateError('نام مسیر الزامی است.');
    final data = <String, Object?>{
      'route_id': routeId,
      'peak_id': route.peakId,
      'name': normalizedName,
      'gpx_file_path': route.gpxFilePath,
      'route_length_km': route.routeLengthKm,
      'elevation_gain_m': route.elevationGainM,
      'trailhead': PersianNormalizer.normalizeNullableText(route.trailhead),
      'trailhead_latitude': route.trailheadLatitude,
      'trailhead_longitude': route.trailheadLongitude,
      'trailhead_elevation_m': route.trailheadElevationM,
      'source_owner': PersianNormalizer.normalizeNullableText(route.sourceOwner),
      'source_url': route.sourceUrl?.trim(),
      'price_irr': route.priceIrr,
      'currency': route.currency,
      'publication_status': route.publicationStatus,
      'route_count_hint': route.routeCountHint,
      'difficulty': PersianNormalizer.normalizeNullableText(route.difficulty),
      'estimated_duration': PersianNormalizer.normalizeNullableText(route.estimatedDuration),
      'best_season': PersianNormalizer.normalizeNullableText(route.bestSeason),
      'route_type': PersianNormalizer.normalizeNullableText(route.routeType),
      'file_sha256': route.fileSha256,
      'version': route.version,
      'is_deleted': 0,
      'data_flags': _routeDataFlags(route),
      'updated_at_utc': ts.$1,
      'updated_at_jalali': ts.$2,
    };
    await _db.transaction((txn) async {
      if (existing.isEmpty) {
        data['download_count'] = 0;
        data['created_at_utc'] = ts.$1;
        data['created_at_jalali'] = ts.$2;
        await txn.insert('gpx_routes', data);
        await txn.insert('route_revenue_shares', {'route_id': routeId, 'owner_percent': 0, 'admin_percent': 100}, conflictAlgorithm: ConflictAlgorithm.ignore);
        await _audit(txn, entityType: 'route', entityId: routeId, peakId: route.peakId,
            action: 'add', actor: _actor(manager), ts: ts);
        await _enqueueSync(txn, 'route', routeId, 'add', data, ts);
      } else {
        await txn.update('gpx_routes', data, where: 'route_id=?', whereArgs: [routeId]);
        await _audit(txn, entityType: 'route', entityId: routeId, peakId: route.peakId,
            action: 'update', actor: _actor(manager), ts: ts);
        await _enqueueSync(txn, 'route', routeId, 'update', data, ts);
      }
    });
    return routeId;
  }

  String? _routeDataFlags(GpxRoute route) {
    final flags = <String>[];
    if (route.trailheadLatitude == null || route.trailheadLongitude == null) flags.add('missing_trailhead_coordinates');
    if (!route.hasFile) flags.add('missing_gpx_file');
    return flags.isEmpty ? null : flags.join(',');
  }

  Future<void> softDeleteRoute(GpxRoute route) async {
    final manager = await _requireManager();
    final ts = _timestamps();
    await _db.transaction((txn) async {
      await txn.update('gpx_routes', {
        'is_deleted': 1,
        'deleted_at_utc': ts.$1,
        'deleted_at_jalali': ts.$2,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      }, where: 'route_id=?', whereArgs: [route.routeId]);
      await _audit(txn, entityType: 'route', entityId: route.routeId, peakId: route.peakId,
          action: 'soft_delete', actor: _actor(manager), ts: ts);
      await _enqueueSync(txn, 'route', route.routeId, 'soft_delete', const {}, ts);
    });
  }

  Future<List<AuditEntry>> auditForPeak(String peakId) async {
    await _requireManager();
    final rows = await _db.query('audit_log', where: 'peak_id=?', whereArgs: [peakId], orderBy: 'audit_id DESC', limit: 300);
    return rows.map(AuditEntry.fromMap).toList();
  }

  Future<List<EducationCategory>> educationCategories() async {
    final rows = await _db.query('education_categories', where: 'is_active=1', orderBy: 'sort_order,title');
    return rows.map(EducationCategory.fromMap).toList();
  }

  Future<List<EducationContent>> educationContents(String categoryId) async {
    final rows = await _db.query('education_contents', where: "category_id=? AND publication_status='published'", whereArgs: [categoryId], orderBy: 'sort_order,title');
    return rows.map(EducationContent.fromMap).toList();
  }

  Future<UserAccount?> activeUser() async => SessionStore.instance.currentUser;

  Future<void> cacheUserProfile(UserAccount user) async {
    final ts = _timestamps();
    await _db.insert('users', {
      'user_id': user.userId,
      'display_name': user.displayName,
      'mobile': user.mobile,
      'email': user.email,
      'status': user.status,
      'role': user.role,
      'created_at_utc': user.createdAtUtc ?? ts.$1,
      'created_at_jalali': user.createdAtJalali.isEmpty ? ts.$2 : user.createdAtJalali,
      'updated_at_utc': ts.$1,
      'updated_at_jalali': ts.$2,
      'last_login_at_utc': user.lastLoginAtUtc,
      'last_login_at_jalali': user.lastLoginAtJalali,
      'last_activity_at_utc': user.lastActivityAtUtc,
      'last_activity_at_jalali': user.lastActivityAtJalali,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> hasEntitlement(String userId, String routeId) async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS c FROM download_entitlements
      WHERE user_id=? AND route_id=? AND status='active'
        AND (download_limit IS NULL OR download_count < download_limit)
    ''', [userId, routeId]);
    return (rows.first['c'] as num).toInt() > 0;
  }

  Future<PurchaseResult> requestRouteAccess(GpxRoute route) async {
    final user = SessionStore.instance.currentUser;
    if (user == null) return const PurchaseResult('login_required', 'ابتدا وارد حساب کاربری شوید.');
    await cacheUserProfile(user);
    if (!route.isPublished || !route.hasFile) {
      return const PurchaseResult('not_available', 'این GPX هنوز منتشر نشده یا فایل آن ثبت نشده است.');
    }
    if (await hasEntitlement(user.userId, route.routeId)) {
      return const PurchaseResult('entitled', 'مجوز دانلود این GPX قبلاً برای شما صادر شده است.');
    }

    final ts = _timestamps();
    if (route.isFree) {
      final id = 'E-${DateTime.now().microsecondsSinceEpoch}';
      await _db.insert('download_entitlements', {
        'entitlement_id': id,
        'user_id': user.userId,
        'route_id': route.routeId,
        'status': 'active',
        'download_count': 0,
        'granted_at_utc': ts.$1,
        'granted_at_jalali': ts.$2,
      });
      return const PurchaseResult('granted', 'مجوز دانلود رایگان صادر شد.');
    }

    final pending = await _db.query('orders', columns: ['order_id'], where: "user_id=? AND route_id=? AND payment_status='pending'", whereArgs: [user.userId, route.routeId], limit: 1);
    if (pending.isNotEmpty) return const PurchaseResult('pending', 'یک سفارش پرداخت‌نشده برای این GPX از قبل وجود دارد.');

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final orderId = 'O-$suffix';
    await _db.transaction((txn) async {
      await txn.insert('orders', {
        'order_id': orderId, 'user_id': user.userId, 'route_id': route.routeId,
        'amount_irr': route.priceIrr, 'discount_irr': 0, 'payable_irr': route.priceIrr,
        'payment_status': 'pending', 'created_at_utc': ts.$1, 'created_at_jalali': ts.$2,
      });
      await txn.insert('payments', {
        'payment_id': 'PAY-$suffix', 'order_id': orderId, 'user_id': user.userId,
        'amount_irr': route.priceIrr, 'payment_status': 'pending',
        'created_at_utc': ts.$1, 'created_at_jalali': ts.$2,
      });
      await txn.insert('gpx_purchases', {
        'purchase_id': 'PUR-$suffix', 'order_id': orderId, 'user_id': user.userId,
        'route_id': route.routeId, 'purchase_status': 'pending', 'price_irr': route.priceIrr,
        'created_at_utc': ts.$1, 'created_at_jalali': ts.$2,
      });
      await txn.insert('transactions', {
        'transaction_id': 'T-$suffix', 'user_id': user.userId,
        'order_id': orderId, 'route_id': route.routeId, 'transaction_type': 'purchase',
        'amount_irr': route.priceIrr, 'status': 'pending',
        'created_at_utc': ts.$1, 'created_at_jalali': ts.$2,
      });
    });
    return const PurchaseResult('pending', 'سفارش ایجاد شد. تأیید پرداخت باید در Backend امن انجام شود.');
  }

  Future<List<ProvinceStat>> provinceStats() async {
    final rows = await _db.query('province_stats');
    final stats = rows.map(ProvinceStat.fromMap).toList();
    final rank = <String, int>{for (var i = 0; i < officialProvinceOrder.length; i++) officialProvinceOrder[i]: i};
    stats.sort((a, b) => (rank[a.province] ?? 999).compareTo(rank[b.province] ?? 999));
    return stats;
  }

  Future<Map<String, int>> fieldCompleteness() async {
    final out = <String, int>{};

    const numericPositive = <String>[
      'elevation', 'map_elevation', 'trailhead_elevation_m',
      'elevation_gain_m', 'route_length_km',
    ];
    for (final field in numericPositive) {
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM peaks '
        'WHERE is_deleted=0 AND $field IS NOT NULL AND CAST($field AS REAL)>0',
      );
      out[field] = (rows.first['c'] as num).toInt();
    }

    const textFields = <String>[
      'name', 'province', 'county', 'district', 'route', 'trailhead', 'difficulty',
      'best_season', 'route_status', 'mountain_range', 'description',
    ];
    for (final field in textFields) {
      final rows = await _db.rawQuery(
        "SELECT COUNT(*) AS c FROM peaks WHERE is_deleted=0 "
        "AND $field IS NOT NULL "
        "AND TRIM(CAST($field AS TEXT))<>'' "
        "AND LOWER(TRIM(CAST($field AS TEXT))) NOT IN "
        "('n/a','na','unknown','نامشخص','-','--','?')",
      );
      out[field] = (rows.first['c'] as num).toInt();
    }

    final summitCoordinates = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM peaks WHERE is_deleted=0 '
      'AND latitude IS NOT NULL AND longitude IS NOT NULL '
      'AND latitude BETWEEN 20 AND 45 AND longitude BETWEEN 40 AND 65',
    );
    out['latitude'] = (summitCoordinates.first['c'] as num).toInt();

    final routeTrail = await _db.rawQuery(
      'SELECT COUNT(DISTINCT peak_id) AS c FROM gpx_routes '
      'WHERE is_deleted=0 AND trailhead_latitude IS NOT NULL '
      'AND trailhead_longitude IS NOT NULL '
      'AND trailhead_latitude BETWEEN 20 AND 45 '
      'AND trailhead_longitude BETWEEN 40 AND 65',
    );
    out['trailhead_coordinates'] = (routeTrail.first['c'] as num).toInt();

    final routeDuration = await _db.rawQuery(
      "SELECT COUNT(DISTINCT peak_id) AS c FROM gpx_routes "
      "WHERE is_deleted=0 AND estimated_duration IS NOT NULL "
      "AND TRIM(estimated_duration)<>'' "
      "AND LOWER(TRIM(estimated_duration)) NOT IN "
      "('n/a','na','unknown','نامشخص','-','--','?')",
    );
    out['route_duration'] = (routeDuration.first['c'] as num).toInt();

    final gpxRoute = await _db.rawQuery(
      'SELECT COUNT(DISTINCT peak_id) AS c FROM gpx_routes WHERE is_deleted=0',
    );
    out['gpx_route'] = (gpxRoute.first['c'] as num).toInt();
    return out;
  }

  Future<Map<String, int>> qualityCounts() async {
    final rows = await _db.rawQuery('SELECT data_quality_status AS q, COUNT(*) AS c FROM peaks WHERE is_deleted=0 GROUP BY data_quality_status');
    return {for (final row in rows) '${row['q']}': (row['c'] as num).toInt()};
  }

  Future<int> auditCount() => _scalarCount('audit_log');
  Future<int> gpxRouteCount() => _scalarCount('gpx_routes', where: 'is_deleted=0');
  Future<int> userCount() => _scalarCount('users');
  Future<int> downloadCount() => _scalarCount('download_events');
  Future<int> pendingOrderCount() => _scalarCount('orders', where: "payment_status='pending'");

  Future<int> _scalarCount(String table, {String? where}) async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM $table${where == null ? '' : ' WHERE $where'}');
    return (rows.first['c'] as num).toInt();
  }

  Future<Map<String, dynamic>> exportSafeData({required bool includeReferenceData}) async {
    final settings = await _db.query('app_settings');
    final safeSettings = settings.where((row) {
      final key = '${row['key']}'.toLowerCase();
      return !key.contains('token') && !key.contains('password') && !key.contains('otp') && !key.contains('auth') && key != 'active_user_id';
    }).map((e) => Map<String, Object?>.from(e)).toList();

    final data = <String, dynamic>{
      'favorites': await _db.query('peaks', columns: ['id', 'favorite'], where: 'favorite=1 AND is_deleted=0'),
      'app_settings': safeSettings,
    };
    if (includeReferenceData) {
      data['peaks'] = await _db.query('peaks');
      data['gpx_routes'] = await _db.query('gpx_routes');
      data['audit_log'] = await _db.query('audit_log');
    }
    return data;
  }

  Future<void> importSafeData(Map<String, dynamic> data, {required bool includeReferenceData}) async {
    if (includeReferenceData) await _requireManager();
    await _db.transaction((txn) async {
      if (includeReferenceData) {
        for (final item in (data['peaks'] as List? ?? const [])) {
          if (item is! Map) continue;
          final map = _normalizePeakEditableMap(Map<String, Object?>.from(item));
          final range = await _ensureMountainRange(txn, map['mountain_range']?.toString());
          map['mountain_range_id'] = range?.$1;
          map['mountain_range'] = range?.$2;
          final quality = _qualityForPeakData(map);
          map['data_flags'] = quality.flags;
          map['data_quality_status'] = quality.quality;
          map['search_text'] = _peakSearchTextFromData(map);
          await txn.insert('peaks', map, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final item in (data['gpx_routes'] as List? ?? const [])) {
          if (item is! Map) continue;
          final map = Map<String, Object?>.from(item);
          for (final field in const [
            'name', 'trailhead', 'source_owner', 'difficulty', 'estimated_duration',
            'best_season', 'route_type',
          ]) {
            if (map[field] != null) {
              map[field] = PersianNormalizer.normalizeNullableText(map[field]?.toString());
            }
          }
          await txn.insert('gpx_routes', map, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await _refreshMountainRangeUsage(txn);
        for (final item in (data['audit_log'] as List? ?? const [])) {
          if (item is Map) {
            final map = Map<String, Object?>.from(item)..remove('audit_id');
            await txn.insert('audit_log', map);
          }
        }
      }
      for (final item in (data['favorites'] as List? ?? const [])) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id != null) await txn.update('peaks', {'favorite': 1}, where: 'id=?', whereArgs: [id]);
      }
      for (final item in (data['app_settings'] as List? ?? const [])) {
        if (item is! Map) continue;
        final key = item['key']?.toString();
        if (key == null || _isSensitiveSetting(key)) continue;
        await txn.insert('app_settings', {'key': key, 'value': item['value']}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  bool _isSensitiveSetting(String key) {
    final k = key.toLowerCase();
    return k.contains('token') || k.contains('password') || k.contains('otp') || k.contains('auth') || k == 'active_user_id';
  }

  Future<void> recordBackup({required String id, required String type, String? fileName, required String status}) async {
    final ts = _timestamps();
    await _db.insert('backup_history', {
      'backup_id': id,
      'backup_type': type,
      'file_name': fileName,
      'status': status,
      'created_at_utc': ts.$1,
      'created_at_jalali': ts.$2,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (status == 'success') await setSetting('last_backup_at_jalali', ts.$2);
  }

  Future<String?> lastBackupAtJalali() => getSetting('last_backup_at_jalali');

  Future<void> _audit(
    Transaction txn, {
    required String entityType,
    required String entityId,
    String? peakId,
    required String action,
    String? field,
    Object? before,
    Object? after,
    required String actor,
    required (String, String) ts,
  }) async {
    await txn.insert('audit_log', {
      'peak_id': peakId,
      'entity_type': entityType,
      'entity_id': entityId,
      'action': action,
      'field_name': field,
      'old_value': before?.toString(),
      'new_value': after?.toString(),
      'actor': actor,
      'changed_at_utc': ts.$1,
      'changed_at_jalali': ts.$2,
    });
  }

  Future<void> _enqueueSync(
    Transaction txn,
    String entityType,
    String entityId,
    String operation,
    Map<String, Object?> payload,
    (String, String) ts,
  ) async {
    await txn.insert('sync_outbox', {
      'outbox_id': 'OUT-${DateTime.now().microsecondsSinceEpoch}',
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'sync_status': 'pending',
      'attempt_count': 0,
      'created_at_utc': ts.$1,
      'created_at_jalali': ts.$2,
    });
  }

  bool _sameValue(Object? a, Object? b) {
    if (a == null && b == null) return true;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return a?.toString() == b?.toString();
  }

  String _normalize(String value) => PersianNormalizer.normalizeSearch(value);
}
