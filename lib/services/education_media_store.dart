import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../data/peak_repository.dart';
import '../models/education_media.dart';

class EducationMediaStore {
  EducationMediaStore._();
  static final instance = EducationMediaStore._();

  Future<Database> _open() async {
    final db = await openDatabase(PeakRepository.instance.databasePath);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS education_media (
        media_id TEXT PRIMARY KEY,
        content_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        caption TEXT,
        url TEXT,
        blob_data BLOB,
        mime_type TEXT,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS education_media_content ON education_media(content_id, created_at_utc)',
    );
    return db;
  }

  Future<List<EducationMedia>> listForContent(String contentId) async {
    final db = await _open();
    try {
      final rows = await db.query(
        'education_media',
        where: 'content_id=?',
        whereArgs: [contentId],
        orderBy: 'created_at_utc, media_id',
      );
      return rows.map(EducationMedia.fromMap).toList(growable: false);
    } finally {
      await db.close();
    }
  }

  Future<void> addImage({
    required String contentId,
    required Uint8List bytes,
    required String mimeType,
    String? caption,
  }) async {
    final db = await _open();
    try {
      final now = DateTime.now().toUtc();
      await db.insert('education_media', {
        'media_id': 'EDU-MEDIA-${now.microsecondsSinceEpoch}',
        'content_id': contentId,
        'kind': 'image',
        'caption': _clean(caption),
        'url': null,
        'blob_data': bytes,
        'mime_type': mimeType,
        'created_at_utc': now.toIso8601String(),
      });
    } finally {
      await db.close();
    }
  }

  Future<void> addMediaLink({
    required String contentId,
    required String url,
    String? caption,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('آدرس مدیا معتبر نیست.');
    }
    final db = await _open();
    try {
      final now = DateTime.now().toUtc();
      await db.insert('education_media', {
        'media_id': 'EDU-MEDIA-${now.microsecondsSinceEpoch}',
        'content_id': contentId,
        'kind': 'media',
        'caption': _clean(caption),
        'url': normalized,
        'blob_data': null,
        'mime_type': null,
        'created_at_utc': now.toIso8601String(),
      });
    } finally {
      await db.close();
    }
  }

  Future<void> delete(String mediaId) async {
    final db = await _open();
    try {
      await db.delete('education_media', where: 'media_id=?', whereArgs: [mediaId]);
    } finally {
      await db.close();
    }
  }

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
