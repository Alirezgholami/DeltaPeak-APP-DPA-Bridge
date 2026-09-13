import 'package:flutter/material.dart';
import '../app_info.dart';
import '../data/peak_repository.dart';
import '../models/database_info.dart';
import '../models/province_stat.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  DatabaseInfo? _info;
  List<ProvinceStat> _provinces = const [];
  Map<String, int> _quality = const {};
  int _auditCount = 0;
  int _gpxCount = 0;
  int _userCount = 0;
  int _downloadCount = 0;
  int _pendingOrders = 0;
  Map<String, int> _qualityCounts = const {};
  String? _lastBackup;
  bool _loading = true;

  static const _labels = <String, String>{
    'name': 'نام قله', 'province': 'استان',
    'elevation': 'ارتفاع قله (تابلو)', 'map_elevation': 'ارتفاع قله (Map)',
    'county': 'شهرستان', 'district': 'بخش/دهستان', 'mountain_range': 'رشته‌کوه',
    'latitude': 'مختصات قله', 'description': 'توضیحات کامل',
    'route': 'مسیر اصلی Legacy', 'trailhead': 'نقطه شروع/ابتدای پاکوب',
    'trailhead_coordinates': 'مختصات ابتدای پاکوب',
    'trailhead_elevation_m': 'ارتفاع نقطه شروع', 'elevation_gain_m': 'ارتفاع‌گیری',
    'route_length_km': 'طول مسیر', 'route_duration': 'مدت مسیر',
    'difficulty': 'درجه سختی', 'best_season': 'بهترین فصل',
    'route_status': 'وضعیت مسیر', 'gpx_route': 'مسیر GPX',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = PeakRepository.instance;
    final result = await Future.wait<dynamic>([
      repo.databaseInfo(), repo.provinceStats(), repo.fieldCompleteness(), repo.auditCount(),
      repo.gpxRouteCount(), repo.userCount(), repo.downloadCount(), repo.pendingOrderCount(),
      repo.qualityCounts(), repo.lastBackupAtJalali(),
    ]);
    if (!mounted) return;
    setState(() {
      _info = result[0] as DatabaseInfo;
      _provinces = result[1] as List<ProvinceStat>;
      _quality = result[2] as Map<String, int>;
      _auditCount = result[3] as int;
      _gpxCount = result[4] as int;
      _userCount = result[5] as int;
      _downloadCount = result[6] as int;
      _pendingOrders = result[7] as int;
      _qualityCounts = result[8] as Map<String, int>;
      _lastBackup = result[9] as String?;
      _loading = false;
    });
  }

  double _pct(int count) {
    final total = _info?.recordCount ?? 0;
    if (total == 0) return 0;
    return (count / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('آمار و وضعیت بانک')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _identityCard(), const SizedBox(height: 12),
                    _summaryCard(), const SizedBox(height: 12),
                    _qualityCard(), const SizedBox(height: 12),
                    _provinceCard(), const SizedBox(height: 24),
                  ],
                ),
              ),
      );

  Widget _identityCard() {
    final info = _info!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('شناسنامه نسخه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Divider(),
          _row('نسخه اپ', 'DPA v${AppInfo.appVersion}+${AppInfo.buildNumber}'),
          _row('نسخه بانک', info.version),
          _row('Schema', info.schemaVersion),
          _row('Dataset', info.datasetRevision),
          _row('فایل مرجع', info.sourceFile),
          _row('SHA-256', info.sourceSha256),
          _row('ساخت بانک (جلالی)', info.generatedAtJalali),
          _row('آخرین Backup', _lastBackup ?? 'ثبت نشده'),
        ]),
      ),
    );
  }

  Widget _summaryCard() {
    final info = _info!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('آمار کل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Divider(),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metric('رکورد منبع', '${info.sourceRecordCount}'),
            _metric('قله قابل انتشار', '${info.recordCount}'),
            _metric('Exclusion کنترل‌شده', '${info.controlledExclusionCount}'),
            _metric('استان رسمی', '${info.provinceLabelCount}'),
            _metric('GPX Route', '$_gpxCount'),
            _metric('ویرایش Owner', '$_auditCount'),
            _metric('پروفایل Cache کاربران', '$_userCount'),
            _metric('دانلود GPX', '$_downloadCount'),
            _metric('سفارش pending', '$_pendingOrders'),
            _metric('داده کامل', '${_qualityCounts['complete'] ?? 0}'),
            _metric('ناقص', '${_qualityCounts['incomplete'] ?? 0}'),
            _metric('نیازمند بررسی', '${_qualityCounts['needs_review'] ?? 0}'),
          ]),
        ]),
      ),
    );
  }

  Widget _qualityCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('کامل‌بودن اطلاعات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Divider(),
            for (final entry in _labels.entries)
              _completenessRow(entry.value, _quality[entry.key] ?? 0),
          ]),
        ),
      );

  Widget _completenessRow(String label, int completed) {
    final total = _info!.recordCount;
    final safeCompleted = completed.clamp(0, total).toInt();
    final missing = total - safeCompleted;
    final pct = _pct(safeCompleted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        label: '$label: $safeCompleted تکمیل، $missing باقی‌مانده از $total',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 9,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.centerRight,
                        children: [
                          const ColoredBox(color: Colors.red),
                          FractionallySizedBox(
                            widthFactor: pct,
                            alignment: Alignment.centerRight,
                            child: const ColoredBox(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    children: [
                      TextSpan(text: '$total', style: const TextStyle(color: Colors.blue)),
                      const TextSpan(text: ' − '),
                      TextSpan(text: '$safeCompleted', style: const TextStyle(color: Colors.green)),
                      const TextSpan(text: ' = '),
                      TextSpan(text: '$missing', style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _provinceCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('استان‌ها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Divider(),
            for (final p in _provinces)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [Expanded(child: Text(p.province)), Text('${p.totalRecords}')]),
              ),
          ]),
        ),
      );

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('$label: $value'),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 145, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: SelectableText(value)),
        ]),
      );
}
