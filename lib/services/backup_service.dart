import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../app_info.dart';
import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../utils/jalali.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupService {
  BackupService._();
  static final instance = BackupService._();

  bool get _canIncludeReference => SessionStore.instance.canManageReferenceData;

  Future<Uint8List> createBackupBytes() async {
    final repo = PeakRepository.instance;
    final data = await repo.exportSafeData(includeReferenceData: _canIncludeReference);
    final info = await repo.databaseInfo();
    final now = DateTime.now().toUtc();
    final manifest = <String, dynamic>{
      'format': 'DPA_BACKUP',
      'backup_format_version': 1,
      'app_version': AppInfo.appVersion,
      'build_number': AppInfo.buildNumber,
      'database_version': info.version,
      'schema_version': int.tryParse(info.schemaVersion) ?? 0,
      'created_at_utc': now.toIso8601String(),
      'created_at_jalali': JalaliDate.now(),
      'includes_reference_data': _canIncludeReference,
      'contains_authentication': false,
    };

    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final dataBytes = utf8.encode(jsonEncode(data));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    archive.addFile(ArchiveFile('data.json', dataBytes.length, dataBytes));

    final routes = data['gpx_routes'];
    if (routes is List) {
      final added = <String>{};
      for (final item in routes) {
        if (item is! Map) continue;
        final filePath = item['gpx_file_path']?.toString();
        if (filePath == null || filePath.isEmpty) continue;
        final file = File(filePath);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final digest = (item['file_sha256']?.toString().trim().isNotEmpty ?? false)
            ? item['file_sha256'].toString()
            : sha256.convert(bytes).toString();
        final name = 'gpx/$digest.gpx';
        if (added.add(name)) archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw const BackupException('ساخت فایل Backup ناموفق بود.');
    return Uint8List.fromList(encoded);
  }

  Future<void> saveBackupWithPicker() async {
    final bytes = await createBackupBytes();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
    final name = 'DPA_BACKUP_$stamp.dpa.zip';
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره Backup DPA',
        fileName: name,
        bytes: bytes,
      );
      if (result == null) return;
      await PeakRepository.instance.recordBackup(
        id: 'B-${DateTime.now().microsecondsSinceEpoch}',
        type: 'manual_backup',
        fileName: name,
        status: 'success',
      );
    } catch (e) {
      await PeakRepository.instance.recordBackup(
        id: 'B-${DateTime.now().microsecondsSinceEpoch}',
        type: 'manual_backup',
        fileName: name,
        status: 'failed',
      );
      rethrow;
    }
  }

  Future<void> exportJsonWithPicker() async {
    final data = await PeakRepository.instance.exportSafeData(includeReferenceData: _canIncludeReference);
    final payload = <String, dynamic>{
      'format': 'DPA_EXPORT',
      'export_version': 1,
      'schema_version': int.parse(AppInfo.expectedSchemaVersion),
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'contains_authentication': false,
      'data': data,
    };
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)));
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
    await FilePicker.platform.saveFile(
      dialogTitle: 'Export داده‌های DPA',
      fileName: 'DPA_EXPORT_$stamp.json',
      bytes: bytes,
    );
  }

  Future<void> pickAndRestoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const BackupException('خواندن فایل Backup ممکن نشد.');
    await restoreBackupBytes(Uint8List.fromList(bytes));
  }

  Future<void> pickAndImportJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const BackupException('خواندن فایل Import ممکن نشد.');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const BackupException('فرمت Import معتبر نیست.');
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['format'] != 'DPA_EXPORT') throw const BackupException('این فایل DPA Export نیست.');
    final schema = int.tryParse('${payload['schema_version']}') ?? 0;
    if (schema > int.parse(AppInfo.expectedSchemaVersion)) {
      throw const BackupException('فایل با Schema جدیدتری ساخته شده و این نسخه نمی‌تواند آن را Import کند.');
    }
    final data = payload['data'];
    if (data is! Map) throw const BackupException('بخش data در فایل Import وجود ندارد.');
    await PeakRepository.instance.importSafeData(
      Map<String, dynamic>.from(data),
      includeReferenceData: _canIncludeReference,
    );
  }

  Future<void> restoreBackupBytes(Uint8List bytes) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const BackupException('فایل Backup خراب یا نامعتبر است.');
    }
    ArchiveFile? manifestEntry;
    ArchiveFile? dataEntry;
    final gpxEntries = <ArchiveFile>[];
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.contains('../')) {
        throw const BackupException('Backup شامل مسیر فایل ناامن است.');
      }
      if (name == 'manifest.json') manifestEntry = entry;
      if (name == 'data.json') dataEntry = entry;
      if (name.startsWith('gpx/') && name.endsWith('.gpx')) gpxEntries.add(entry);
    }
    if (manifestEntry == null || dataEntry == null) {
      throw const BackupException('manifest.json یا data.json در Backup وجود ندارد.');
    }

    final manifest = jsonDecode(utf8.decode(_entryBytes(manifestEntry)));
    if (manifest is! Map || manifest['format'] != 'DPA_BACKUP') {
      throw const BackupException('فرمت Backup متعلق به DPA نیست.');
    }
    final schema = int.tryParse('${manifest['schema_version']}') ?? 0;
    if (schema > int.parse(AppInfo.expectedSchemaVersion)) {
      throw const BackupException('Backup با Schema جدیدتری ساخته شده است. ابتدا DPA را به‌روزرسانی کنید.');
    }

    final safety = await createBackupBytes();
    final docs = await getApplicationDocumentsDirectory();
    final safetyDir = Directory(p.join(docs.path, 'safety_snapshots'));
    await safetyDir.create(recursive: true);
    final safetyPath = p.join(safetyDir.path, 'pre_restore_${DateTime.now().millisecondsSinceEpoch}.dpa.zip');
    await File(safetyPath).writeAsBytes(safety, flush: true);

    final decodedData = jsonDecode(utf8.decode(_entryBytes(dataEntry)));
    if (decodedData is! Map) throw const BackupException('داده Backup معتبر نیست.');
    final data = Map<String, dynamic>.from(decodedData);

    if (_canIncludeReference && gpxEntries.isNotEmpty) {
      final gpxDir = Directory(p.join(docs.path, 'gpx'));
      await gpxDir.create(recursive: true);
      for (final entry in gpxEntries) {
        final base = p.basename(entry.name);
        if (!RegExp(r'^[a-fA-F0-9]{64}\.gpx$').hasMatch(base)) continue;
        final target = File(p.join(gpxDir.path, base));
        if (!await target.exists()) await target.writeAsBytes(_entryBytes(entry), flush: true);
      }
      final routes = data['gpx_routes'];
      if (routes is List) {
        for (final item in routes) {
          if (item is! Map) continue;
          final sha = item['file_sha256']?.toString();
          if (sha != null && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
            item['gpx_file_path'] = p.join(gpxDir.path, '$sha.gpx');
          }
        }
      }
    }

    await PeakRepository.instance.importSafeData(data, includeReferenceData: _canIncludeReference);
    await PeakRepository.instance.recordBackup(
      id: 'R-${DateTime.now().microsecondsSinceEpoch}',
      type: 'restore',
      fileName: 'imported_backup',
      status: 'success',
    );
  }

  List<int> _entryBytes(ArchiveFile entry) {
    final content = entry.content;
    if (content is List<int>) return content;
    throw const BackupException('محتوای یکی از فایل‌های Backup قابل خواندن نیست.');
  }
}
