import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../utils/jalali.dart';
import '../utils/persian_normalizer.dart';

/// DPA canonical identity migration.
/// One normalized peak name inside the same province + county is one peak.
/// Different ascent routes are preserved under that peak; duplicate routes are
/// archived (not physically destroyed) so old purchase/download references stay valid.
class PeakIdentityDeduper {
  PeakIdentityDeduper._();

  static const migrationId =
      'PEAK-DEDUP-NAME-PROVINCE-COUNTY-V2-20260913';

  static String _norm(Object? value) => value == null
      ? ''
      : PersianNormalizer.normalizeSearch(
          value.toString().replaceAll('\u200c', ' '),
        );

  static bool _has(Object? value) {
    if (value == null) return false;
    if (value is String) {
      return value.trim().isNotEmpty &&
          !PersianNormalizer.isMissingPlaceholder(value);
    }
    return true;
  }

  static (String, String) _ts() {
    final now = DateTime.now().toUtc();
    return (now.toIso8601String(), JalaliDate.fromDateTime(now.toLocal()));
  }

  static bool _sameRoute(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final aSha = '${a['file_sha256'] ?? ''}'.trim().toLowerCase();
    final bSha = '${b['file_sha256'] ?? ''}'.trim().toLowerCase();
    if (aSha.isNotEmpty && bSha.isNotEmpty) return aSha == bSha;
    final aName = _norm(a['name']);
    if (aName.isEmpty || aName != _norm(b['name'])) return false;
    return _norm(a['trailhead']) == _norm(b['trailhead']);
  }

  static int _score(Map<String, Object?> row) {
    const weights = <String, int>{
      'latitude': 10,
      'longitude': 10,
      'county': 6,
      'elevation': 6,
      'map_elevation': 5,
      'route': 5,
      'trailhead': 5,
      'mountain_range': 4,
      'elevation_gain_m': 4,
      'route_length_km': 4,
      'description': 3,
      'district': 3,
      'source_url': 2,
    };
    var score = 0;
    for (final e in weights.entries) {
      if (_has(row[e.key])) score += e.value;
    }
    if ((row['favorite'] as num?)?.toInt() == 1) score += 10;
    score +=
        math.min((row['route_count'] as num?)?.toInt() ?? 0, 5).toInt() * 3;
    return score;
  }

  static Future<bool> _table(DatabaseExecutor db, String name) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [name],
      ))
          .isNotEmpty;

  static Future<Set<String>> _cols(
    DatabaseExecutor db,
    String table,
  ) async =>
      (await db.rawQuery('PRAGMA table_info($table)'))
          .map((row) => '${row['name']}')
          .toSet();

  static Future<void> _archiveDuplicateRoute(
    DatabaseExecutor txn,
    String keeperPeakId,
    Map<String, Object?> keeper,
    Map<String, Object?> duplicate,
    (String, String) ts,
  ) async {
    const fields = <String>[
      'gpx_file_path',
      'route_length_km',
      'elevation_gain_m',
      'trailhead',
      'trailhead_latitude',
      'trailhead_longitude',
      'trailhead_elevation_m',
      'source_owner',
      'source_url',
      'difficulty',
      'estimated_duration',
      'best_season',
      'route_type',
      'file_sha256',
      'data_flags',
    ];
    final patch = <String, Object?>{};
    for (final field in fields) {
      if (!_has(keeper[field]) && _has(duplicate[field])) {
        patch[field] = duplicate[field];
      }
    }
    final keepPrice = (keeper['price_irr'] as num?)?.toInt() ?? 0;
    final dupPrice = (duplicate['price_irr'] as num?)?.toInt() ?? 0;
    if (dupPrice > keepPrice) patch['price_irr'] = dupPrice;
    final keepDownloads = (keeper['download_count'] as num?)?.toInt() ?? 0;
    final dupDownloads = (duplicate['download_count'] as num?)?.toInt() ?? 0;
    if (dupDownloads > 0) patch['download_count'] = keepDownloads + dupDownloads;
    if ('${keeper['publication_status']}' != 'published' &&
        '${duplicate['publication_status']}' == 'published') {
      patch['publication_status'] = 'published';
    }
    patch['updated_at_utc'] = ts.$1;
    patch['updated_at_jalali'] = ts.$2;
    await txn.update(
      'gpx_routes',
      patch,
      where: 'route_id=?',
      whereArgs: [keeper['route_id']],
    );

    // Keep the redundant route row as an archived tombstone. This hides it from
    // route_count/UI while preserving any historic order/entitlement FK.
    await txn.update(
      'gpx_routes',
      {
        'peak_id': keeperPeakId,
        'is_deleted': 1,
        'deleted_at_utc': ts.$1,
        'deleted_at_jalali': ts.$2,
        'updated_at_utc': ts.$1,
        'updated_at_jalali': ts.$2,
      },
      where: 'route_id=?',
      whereArgs: [duplicate['route_id']],
    );
  }

  static Future<void> _refreshFlags(DatabaseExecutor txn) async {
    final rows = await txn.query(
      'peaks',
      columns: const [
        'id',
        'latitude',
        'longitude',
        'mountain_range',
        'map_elevation',
        'elevation',
        'status',
      ],
      where: 'is_deleted=0',
    );
    final batch = txn.batch();
    for (final row in rows) {
      final flags = <String>[];
      if (row['latitude'] == null || row['longitude'] == null) {
        flags.add('missing_coordinates');
      }
      if (PersianNormalizer.isMissingPlaceholder(row['mountain_range'])) {
        flags.add('missing_mountain_range');
      }
      final mapElevation = (row['map_elevation'] as num?)?.toDouble();
      if (mapElevation == null || mapElevation <= 0) {
        flags.add('missing_map_elevation');
      }
      final summitElevation = (row['elevation'] as num?)?.toDouble();
      if (summitElevation == null || summitElevation <= 0) {
        flags.add('missing_summit_sign_elevation');
      }
      final status = '${row['status'] ?? ''}'.toUpperCase();
      final uncertain = status.contains('AMBIG') ||
          status.contains('UNRESOLVED') ||
          status.contains('P4-') ||
          status.contains('P3 FEATURE') ||
          status.contains('AWAITING');
      if (uncertain) flags.add('needs_manual_review');
      batch.update(
        'peaks',
        {
          'data_flags': flags.isEmpty ? null : flags.join(','),
          'data_quality_status': flags.isEmpty
              ? 'complete'
              : (uncertain ? 'needs_review' : 'incomplete'),
        },
        where: 'id=?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> run(String databasePath) async {
    final db = await openDatabase(databasePath, singleInstance: false);
    try {
      await db.execute('PRAGMA foreign_keys=ON');
      final rows = await db.query('peaks', where: 'is_deleted=0');
      final byIdentity = <String, List<Map<String, Object?>>>{};
      for (final raw in rows) {
        final row = Map<String, Object?>.from(raw);
        final name = _norm(row['name']);
        final province = _norm(row['province']);
        final county = _norm(row['county']);
        if (name.isEmpty || province.isEmpty || county.isEmpty) continue;
        (byIdentity['$name\u0001$province\u0001$county'] ??=
                <Map<String, Object?>>[])
            .add(row);
      }
      final groups =
          byIdentity.values.where((group) => group.length > 1).toList();
      if (groups.isEmpty) return;

      final removals = groups.fold<int>(
        0,
        (sum, group) => sum + group.length - 1,
      );
      if (removals > 250) {
        throw StateError('Peak dedupe safety stop: $removals proposed removals');
      }

      final ts = _ts();
      var removedPeaks = 0;
      var archivedRoutes = 0;
      var preservedRoutes = 0;
      await db.transaction((txn) async {
        for (final group in groups) {
          group.sort((a, b) {
            final score = _score(b).compareTo(_score(a));
            return score != 0
                ? score
                : '${a['id']}'.compareTo('${b['id']}');
          });
          final keeper = Map<String, Object?>.from(group.first);
          final keeperId = '${keeper['id']}';
          final losers = group.skip(1).toList();

          const mergeFields = <String>[
            'aliases',
            'elevation',
            'map_elevation',
            'reported_elevations',
            'district',
            'latitude',
            'longitude',
            'coordinate_source',
            'route',
            'trailhead',
            'trailhead_elevation_m',
            'elevation_gain_m',
            'route_length_km',
            'ascent_time',
            'roundtrip_time',
            'difficulty',
            'best_season',
            'guide_required',
            'route_status',
            'local_alias',
            'mountain_range',
            'description',
            'source',
            'raw_text_sample',
            'source_url',
          ];
          var favorite = (keeper['favorite'] as num?)?.toInt() ?? 0;
          var occurrence =
              (keeper['source_occurrence_count'] as num?)?.toInt() ?? 0;
          for (final loser in losers) {
            for (final field in mergeFields) {
              if (!_has(keeper[field]) && _has(loser[field])) {
                keeper[field] = loser[field];
              }
            }
            favorite = math
                .max(favorite, (loser['favorite'] as num?)?.toInt() ?? 0)
                .toInt();
            occurrence = math
                .max(
                  occurrence,
                  (loser['source_occurrence_count'] as num?)?.toInt() ?? 0,
                )
                .toInt();
          }
          final searchText = PersianNormalizer.normalizeSearch(
            [
              keeper['name'],
              keeper['aliases'],
              keeper['local_alias'],
              keeper['province'],
              keeper['county'],
              keeper['district'],
              keeper['mountain_range'],
            ].where(_has).join(' '),
          );
          await txn.update(
            'peaks',
            {
              for (final field in mergeFields) field: keeper[field],
              'favorite': favorite,
              'source_occurrence_count': occurrence,
              'search_text': searchText,
              'updated_at_utc': ts.$1,
              'updated_at_jalali': ts.$2,
            },
            where: 'id=?',
            whereArgs: [keeperId],
          );

          for (final loser in losers) {
            final loserId = '${loser['id']}';
            final loserRoutes = (await txn.query(
              'gpx_routes',
              where: 'peak_id=? AND is_deleted=0',
              whereArgs: [loserId],
            ))
                .map((row) => Map<String, Object?>.from(row))
                .toList();
            for (final loserRoute in loserRoutes) {
              final keeperRoutes = (await txn.query(
                'gpx_routes',
                where: 'peak_id=? AND is_deleted=0',
                whereArgs: [keeperId],
              ))
                  .map((row) => Map<String, Object?>.from(row))
                  .toList();
              Map<String, Object?>? duplicateOf;
              for (final route in keeperRoutes) {
                if (_sameRoute(route, loserRoute)) {
                  duplicateOf = route;
                  break;
                }
              }
              if (duplicateOf == null) {
                await txn.update(
                  'gpx_routes',
                  {
                    'peak_id': keeperId,
                    'updated_at_utc': ts.$1,
                    'updated_at_jalali': ts.$2,
                  },
                  where: 'route_id=?',
                  whereArgs: [loserRoute['route_id']],
                );
                preservedRoutes++;
              } else {
                await _archiveDuplicateRoute(
                  txn,
                  keeperId,
                  duplicateOf,
                  loserRoute,
                  ts,
                );
                archivedRoutes++;
              }
            }

            // Also re-parent older archived routes. Then the redundant peak can
            // be physically removed because no FK points to it anymore.
            await txn.update(
              'gpx_routes',
              {'peak_id': keeperId},
              where: 'peak_id=?',
              whereArgs: [loserId],
            );
            if (await _table(txn, 'audit_log')) {
              final columns = await _cols(txn, 'audit_log');
              if (columns.contains('peak_id')) {
                await txn.update(
                  'audit_log',
                  {'peak_id': keeperId},
                  where: 'peak_id=?',
                  whereArgs: [loserId],
                );
              }
            }
            await txn.delete('peaks', where: 'id=?', whereArgs: [loserId]);
            removedPeaks++;
          }
        }

        await txn.execute(
          'UPDATE peaks SET route_count=('
          'SELECT COUNT(*) FROM gpx_routes r '
          'WHERE r.peak_id=peaks.id AND r.is_deleted=0'
          ') WHERE is_deleted=0',
        );
        await _refreshFlags(txn);

        if (await _table(txn, 'mountain_ranges')) {
          final peakColumns = await _cols(txn, 'peaks');
          if (peakColumns.contains('mountain_range_id')) {
            await txn.execute(
              'UPDATE mountain_ranges SET usage_count=('
              'SELECT COUNT(*) FROM peaks p WHERE p.is_deleted=0 '
              'AND p.mountain_range_id=mountain_ranges.id)',
            );
          }
        }

        final peakCount = ((await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM peaks WHERE is_deleted=0',
        )).first['c'] as num)
            .toInt();
        final routeCount = ((await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM gpx_routes WHERE is_deleted=0',
        )).first['c'] as num)
            .toInt();
        final metadata = <String, String>{
          'record_count': '$peakCount',
          'official_province_record_count': '$peakCount',
          'route_scaffold_count': '$routeCount',
          'dedupe_same_county_removed_peaks': '$removedPeaks',
          'dedupe_same_route_merged': '$archivedRoutes',
          'dedupe_distinct_routes_preserved': '$preservedRoutes',
        };
        for (final entry in metadata.entries) {
          await txn.insert(
            'metadata',
            {'key': entry.key, 'value': entry.value},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        if (await _table(txn, 'data_migrations')) {
          await txn.insert(
            'data_migrations',
            {
              'migration_id': migrationId,
              'source_label':
                  'same normalized name + province + county; distinct routes preserved',
              'applied_at_utc': ts.$1,
              'changed_fields': removedPeaks,
              'inserted_routes': preservedRoutes,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || '${integrity.first.values.first}' != 'ok') {
        throw StateError('Peak dedupe integrity check failed');
      }
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) {
        throw StateError('Peak dedupe foreign-key check failed: ${fk.take(3)}');
      }
    } finally {
      await db.close();
    }
  }
}
