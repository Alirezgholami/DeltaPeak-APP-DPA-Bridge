import 'package:sqflite/sqflite.dart';

import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../models/education.dart';

class ManagedEducationContent {
  const ManagedEducationContent({
    required this.contentId,
    required this.categoryId,
    required this.title,
    required this.body,
    required this.publicationStatus,
    required this.sortOrder,
  });

  final String contentId;
  final String categoryId;
  final String title;
  final String body;
  final String publicationStatus;
  final int sortOrder;

  bool get isDraft => publicationStatus == 'draft';
  bool get isPublished => publicationStatus == 'published';
  bool get isArchived => publicationStatus == 'archived';

  EducationContent toEducationContent() => EducationContent(
        contentId: contentId,
        categoryId: categoryId,
        title: title,
        body: body,
      );

  factory ManagedEducationContent.fromMap(Map<String, Object?> map) =>
      ManagedEducationContent(
        contentId: (map['content_id'] ?? '').toString(),
        categoryId: (map['category_id'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        body: (map['body'] ?? '').toString(),
        publicationStatus:
            (map['publication_status'] ?? 'published').toString(),
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class EducationContentStore {
  EducationContentStore._();
  static final instance = EducationContentStore._();

  static const allowedStatuses = <String>{'draft', 'published', 'archived'};

  void _requireManager() {
    if (!SessionStore.instance.canManageReferenceData) {
      throw StateError('این بخش فقط برای Owner و Admin مجاز است.');
    }
  }

  Future<Database> _open() async {
    final db = await openDatabase(PeakRepository.instance.databasePath);
    await _ensureSchema(db);
    return db;
  }

  Future<Set<String>> _columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => '${row['name']}').toSet();
  }

  Future<void> _ensureSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='education_contents'",
    );
    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE education_contents (
          content_id TEXT PRIMARY KEY,
          category_id TEXT NOT NULL,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          publication_status TEXT NOT NULL DEFAULT 'draft',
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
    } else {
      final cols = await _columns(db, 'education_contents');
      if (!cols.contains('publication_status')) {
        await db.execute(
          "ALTER TABLE education_contents ADD COLUMN publication_status TEXT NOT NULL DEFAULT 'published'",
        );
      }
      if (!cols.contains('sort_order')) {
        await db.execute(
          'ALTER TABLE education_contents ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
        );
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS education_change_log (
        change_id INTEGER PRIMARY KEY AUTOINCREMENT,
        content_id TEXT NOT NULL,
        action TEXT NOT NULL,
        old_status TEXT,
        new_status TEXT,
        actor_role TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS education_contents_status_idx '
      'ON education_contents(publication_status, category_id, sort_order)',
    );
  }

  Future<List<ManagedEducationContent>> listAll({
    String? categoryId,
    String? status,
  }) async {
    _requireManager();
    if (status != null && !allowedStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final db = await _open();
    try {
      final whereParts = <String>[];
      final args = <Object?>[];
      if (categoryId != null && categoryId.isNotEmpty) {
        whereParts.add('category_id=?');
        args.add(categoryId);
      }
      if (status != null) {
        whereParts.add('publication_status=?');
        args.add(status);
      }
      final rows = await db.query(
        'education_contents',
        where: whereParts.isEmpty ? null : whereParts.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'category_id, sort_order, title',
      );
      return rows.map(ManagedEducationContent.fromMap).toList(growable: false);
    } finally {
      await db.close();
    }
  }

  Future<Map<String, int>> statusCounts() async {
    _requireManager();
    final db = await _open();
    try {
      final rows = await db.rawQuery('''
        SELECT publication_status, COUNT(*) AS c
        FROM education_contents
        GROUP BY publication_status
      ''');
      final out = <String, int>{
        'draft': 0,
        'published': 0,
        'archived': 0,
      };
      for (final row in rows) {
        final status = '${row['publication_status']}';
        if (out.containsKey(status)) {
          out[status] = (row['c'] as num?)?.toInt() ?? 0;
        }
      }
      return out;
    } finally {
      await db.close();
    }
  }

  Future<ManagedEducationContent> save({
    String? contentId,
    required String categoryId,
    required String title,
    required String body,
    required String publicationStatus,
    int? sortOrder,
  }) async {
    _requireManager();
    if (!allowedStatuses.contains(publicationStatus)) {
      throw ArgumentError.value(publicationStatus, 'publicationStatus');
    }
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanBody.isEmpty) {
      throw ArgumentError('عنوان و متن آموزش الزامی است.');
    }

    final db = await _open();
    try {
      final now = DateTime.now().toUtc();
      final id = (contentId == null || contentId.trim().isEmpty)
          ? 'EDU-LOCAL-${now.microsecondsSinceEpoch}'
          : contentId.trim();
      final existing = await db.query(
        'education_contents',
        where: 'content_id=?',
        whereArgs: [id],
        limit: 1,
      );
      final oldStatus = existing.isEmpty
          ? null
          : (existing.first['publication_status'] ?? 'published').toString();

      var order = sortOrder;
      if (order == null) {
        if (existing.isNotEmpty) {
          order = (existing.first['sort_order'] as num?)?.toInt() ?? 0;
        } else {
          final next = await db.rawQuery(
            'SELECT COALESCE(MAX(sort_order),0)+1 AS n FROM education_contents WHERE category_id=?',
            [categoryId],
          );
          order = (next.first['n'] as num?)?.toInt() ?? 1;
        }
      }

      final values = <String, Object?>{
        'content_id': id,
        'category_id': categoryId,
        'title': cleanTitle,
        'body': cleanBody,
        'publication_status': publicationStatus,
        'sort_order': order,
      };
      final cols = await _columns(db, 'education_contents');
      if (cols.contains('updated_at_utc')) {
        values['updated_at_utc'] = now.toIso8601String();
      }
      if (cols.contains('created_at_utc') && existing.isEmpty) {
        values['created_at_utc'] = now.toIso8601String();
      }

      if (existing.isEmpty) {
        await db.insert('education_contents', values);
      } else {
        values.remove('content_id');
        await db.update(
          'education_contents',
          values,
          where: 'content_id=?',
          whereArgs: [id],
        );
      }
      await _log(
        db,
        contentId: id,
        action: existing.isEmpty ? 'create' : 'update',
        oldStatus: oldStatus,
        newStatus: publicationStatus,
      );
      final row = (await db.query(
        'education_contents',
        where: 'content_id=?',
        whereArgs: [id],
        limit: 1,
      )).single;
      return ManagedEducationContent.fromMap(row);
    } finally {
      await db.close();
    }
  }

  Future<void> setStatus(String contentId, String status) async {
    _requireManager();
    if (!allowedStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final db = await _open();
    try {
      final rows = await db.query(
        'education_contents',
        columns: const ['publication_status'],
        where: 'content_id=?',
        whereArgs: [contentId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('محتوای آموزشی پیدا نشد.');
      final oldStatus = '${rows.first['publication_status']}';
      await db.update(
        'education_contents',
        {'publication_status': status},
        where: 'content_id=?',
        whereArgs: [contentId],
      );
      await _log(
        db,
        contentId: contentId,
        action: 'status',
        oldStatus: oldStatus,
        newStatus: status,
      );
    } finally {
      await db.close();
    }
  }

  Future<void> _log(
    Database db, {
    required String contentId,
    required String action,
    String? oldStatus,
    String? newStatus,
  }) async {
    final role = SessionStore.instance.currentUser?.role ??
        (SessionStore.instance.isInternalOwnerMode ? 'owner-internal' : 'unknown');
    await db.insert('education_change_log', {
      'content_id': contentId,
      'action': action,
      'old_status': oldStatus,
      'new_status': newStatus,
      'actor_role': role,
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
