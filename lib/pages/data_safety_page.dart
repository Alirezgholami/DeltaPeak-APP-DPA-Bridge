import 'package:flutter/material.dart';
import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../services/backup_service.dart';
import 'recycle_bin_page.dart';

class DataSafetyPage extends StatefulWidget {
  const DataSafetyPage({super.key});
  @override
  State<DataSafetyPage> createState() => _DataSafetyPageState();
}

class _DataSafetyPageState extends State<DataSafetyPage> {
  bool _busy = false;
  String? _lastBackup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await PeakRepository.instance.lastBackupAtJalali();
    if (mounted) setState(() => _lastBackup = value);
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('عملیات ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = SessionStore.instance.canManageReferenceData;
    return Scaffold(
      appBar: AppBar(title: const Text('Data Safety و پشتیبان‌گیری')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('وضعیت ایمنی داده', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const Divider(),
                Text('آخرین Backup موفق: ${_lastBackup ?? 'ثبت نشده'}'),
                const SizedBox(height: 8),
                const Text('Migration نسخه بانک غیرمخرب است و تغییر Schema حق حذف دیتابیس کاربر را ندارد.'),
                const Text('Password / OTP / Auth Token هرگز داخل Backup یا Export قرار نمی‌گیرند.'),
                if (!canManage)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('برای user عادی Backup فقط Favorites و تنظیمات غیرحساس را شامل می‌شود. Backup کامل بانک و GPX فقط برای Owner/Admin است.'),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _action(Icons.backup_outlined, 'Backup', 'ساخت بسته نسخه‌دار DPA شامل داده مجاز و GPX', () => _run(BackupService.instance.saveBackupWithPicker, 'Backup ذخیره شد.')),
          _action(Icons.restore, 'Restore Backup', 'قبل از Restore یک Safety Snapshot خودکار ساخته می‌شود.', () => _confirmRestore(canManage)),
          _action(Icons.file_download_outlined, 'Export JSON', 'خروجی قابل‌خواندن برای انتقال/تحلیل؛ بدون اطلاعات احراز هویت', () => _run(BackupService.instance.exportJsonWithPicker, 'Export انجام شد.')),
          _action(Icons.file_upload_outlined, 'Import JSON', 'Import به‌صورت Merge و بدون حذف رکوردهای موجود', () => _run(BackupService.instance.pickAndImportJson, 'Import انجام شد.')),
          if (canManage)
            _action(Icons.restore_from_trash_outlined, 'سطل بازیابی', 'مشاهده و بازیابی قله‌های Soft Delete شده', () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const RecycleBinPage()));
            }),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          enabled: !_busy,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );

  Future<void> _confirmRestore(bool canManage) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Backup'),
        content: Text(canManage
            ? 'اطلاعات موجود با داده Backup Merge می‌شود و قبل از عملیات یک Snapshot ایمنی داخلی ساخته خواهد شد. ادامه؟'
            : 'برای حساب user فقط Favorites و تنظیمات غیرحساس بازیابی می‌شوند. ادامه؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ادامه')),
        ],
      ),
    );
    if (ok == true) await _run(BackupService.instance.pickAndRestoreBackup, 'Restore انجام شد.');
  }
}
