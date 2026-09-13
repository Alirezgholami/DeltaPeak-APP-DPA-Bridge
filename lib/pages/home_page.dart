import 'dart:async';
import 'package:flutter/material.dart';
import '../app_info.dart';
import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../models/database_info.dart';
import '../models/peak.dart';
import 'education_page.dart';
import 'owner_edit_page.dart';
import 'peak_detail_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _coordinatesFilterKey = 'home_filter_coordinates';
  static const _gpxFilterKey = 'home_filter_gpx';
  static const _qualityFilterKey = 'home_filter_quality';
  final _controller = TextEditingController();
  List<Peak> _peaks = const [];
  List<String> _provinces = const [];
  DatabaseInfo? _dbInfo;
  String? _province;
  String? _quality;
  String? _missingField;
  bool _favoritesOnly = false;
  bool _coordinatesOnly = false;
  bool _gpxOnly = false;
  bool _loading = true;
  int _resultCount = 0;
  Timer? _debounce;

  bool get _canManage => SessionStore.instance.canManageReferenceData;

  @override
  void initState() {
    super.initState();
    SessionStore.instance.addListener(_sessionChanged);
    _loadInitial();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInitial() async {
    final repo = PeakRepository.instance;
    final result = await Future.wait<dynamic>([repo.provinces(), repo.databaseInfo()]);
    if (!mounted) return;
    _provinces = result[0] as List<String>;
    _dbInfo = result[1] as DatabaseInfo;
    await _loadSearchSettings();
    await _search();
  }

  Future<void> _loadSearchSettings() async {
    final repo = PeakRepository.instance;
    final values = await Future.wait<String?>([
      repo.getSetting(_coordinatesFilterKey),
      repo.getSetting(_gpxFilterKey),
      repo.getSetting(_qualityFilterKey),
    ]);
    if (!mounted) return;
    setState(() {
      _coordinatesOnly = values[0] == '1';
      _gpxOnly = values[1] == '1';
      _quality = switch (values[2]) {
        'incomplete' => 'incomplete',
        'needs_review' => 'needs_review',
        'complete' => 'complete',
        _ => null,
      };
    });
  }

  bool _matchesMissing(Peak peak) => switch (_missingField) {
        null => true,
        'county' => peak.county == null || peak.county!.trim().isEmpty,
        'mountain_range' => peak.mountainRange == null || peak.mountainRange!.trim().isEmpty,
        'summit_elevation' => peak.elevation == null || peak.elevation! <= 0,
        'map_elevation' => peak.mapElevation == null || peak.mapElevation! <= 0,
        'coordinates' => !peak.hasCoordinates,
        'trailhead' => peak.trailhead == null || peak.trailhead!.trim().isEmpty,
        'trailhead_elevation' => peak.trailheadElevationM == null || peak.trailheadElevationM! <= 0,
        'elevation_gain' => peak.elevationGainM == null || peak.elevationGainM! <= 0,
        'route_length' => peak.routeLengthKm == null || peak.routeLengthKm! <= 0,
        'gpx' => true, // SQL-side inverse GPX filter is used below.
        _ => true,
      };

  Future<void> _search() async {
    if (mounted) setState(() => _loading = true);
    final repo = PeakRepository.instance;
    final missingCoordinates = _missingField == 'coordinates';
    final missingGpx = _missingField == 'gpx';
    final result = await repo.search(
      query: _controller.text,
      province: _province,
      qualityFilter: _quality,
      favoritesOnly: _favoritesOnly,
      hasCoordinates: missingCoordinates ? false : (_coordinatesOnly ? true : null),
      hasGpx: missingGpx ? false : (_gpxOnly ? true : null),
    );
    final filtered = result.where(_matchesMissing).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _peaks = filtered;
      _resultCount = filtered.length;
      _loading = false;
    });
  }

  void _queryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _addPeak() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const OwnerEditPage()));
    if (changed == true) await _search();
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    await _loadSearchSettings();
    await _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    SessionStore.instance.removeListener(_sessionChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delta Peak'),
              Text(
                'دانشنامه قله های ایران',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            if (_canManage)
              IconButton(onPressed: _addPeak, icon: const Icon(Icons.add_circle_outline), tooltip: 'افزودن قله'),
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EducationPage())),
              icon: const Icon(Icons.school_outlined),
              tooltip: 'آموزش',
            ),
            IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings_outlined), tooltip: 'تنظیمات'),
          ],
        ),
        body: Column(children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _queryChanged,
              decoration: InputDecoration(
                hintText: 'جست‌وجوی نام قله، شناسه، رشته‌کوه یا شهرستان…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(onPressed: () { _controller.clear(); _search(); }, icon: const Icon(Icons.clear)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _province,
                    decoration: const InputDecoration(labelText: 'استان'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('همه استان‌ها')),
                      ..._provinces.map((p) => DropdownMenuItem<String?>(value: p, child: Text(p))),
                    ],
                    onChanged: (value) { setState(() => _province = value); _search(); },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  height: 56,
                  child: IconButton.filledTonal(
                    tooltip: 'علاقه‌مندی‌ها',
                    onPressed: () {
                      setState(() => _favoritesOnly = !_favoritesOnly);
                      _search();
                    },
                    icon: Icon(
                      _favoritesOnly ? Icons.favorite : Icons.favorite_border,
                      color: _favoritesOnly ? Colors.redAccent : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: DropdownButtonFormField<String?>(
              initialValue: _missingField,
              decoration: const InputDecoration(
                labelText: 'فیلتر موارد نقص برای تکمیل',
                prefixIcon: Icon(Icons.rule_folder_outlined),
              ),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('بدون فیلتر نقص')),
                DropdownMenuItem(value: 'county', child: Text('فاقد شهرستان')),
                DropdownMenuItem(value: 'mountain_range', child: Text('فاقد رشته‌کوه')),
                DropdownMenuItem(value: 'summit_elevation', child: Text('فاقد ارتفاع قله (تابلو)')),
                DropdownMenuItem(value: 'map_elevation', child: Text('فاقد ارتفاع قله (Map)')),
                DropdownMenuItem(value: 'coordinates', child: Text('فاقد مختصات قله')),
                DropdownMenuItem(value: 'trailhead', child: Text('فاقد لوکیشن ابتدای پاکوب')),
                DropdownMenuItem(value: 'trailhead_elevation', child: Text('فاقد ارتفاع شروع')),
                DropdownMenuItem(value: 'elevation_gain', child: Text('فاقد ارتفاع‌گیری')),
                DropdownMenuItem(value: 'route_length', child: Text('فاقد طول مسیر')),
                DropdownMenuItem(value: 'gpx', child: Text('فاقد فایل GPX')),
              ],
              onChanged: (value) {
                setState(() => _missingField = value);
                _search();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(children: [
              Text('$_resultCount قله'),
              const Spacer(),
              if (_canManage) TextButton.icon(onPressed: _addPeak, icon: const Icon(Icons.add), label: const Text('افزودن قله')),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _search,
                    child: _peaks.isEmpty
                        ? ListView(children: const [SizedBox(height: 120), Center(child: Text('نتیجه‌ای پیدا نشد.'))])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _peaks.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _PeakCard(
                              peak: _peaks[i],
                              onTap: () async {
                                await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PeakDetailPage(peak: _peaks[i])));
                                await _search();
                              },
                            ),
                          ),
                  ),
          ),
        ]),
      );

  Widget _header() {
    final info = _dbInfo;
    final user = SessionStore.instance.currentUser;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Wrap(
        spacing: 12,
        runSpacing: 5,
        children: [
          Text('DPA v${AppInfo.appVersion}+${AppInfo.buildNumber}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (info != null) Text('${info.version} • Schema ${info.schemaVersion}'),
          if (info != null) Text('${info.recordCount} قله • ${info.routeScaffoldCount} مسیر'),
          Text(user == null
              ? (SessionStore.instance.isInternalOwnerMode ? 'مالک محلی' : 'مهمان')
              : '${user.mobile} • ${user.role}'),
        ],
      ),
    );
  }
}

class _PeakCard extends StatelessWidget {
  const _PeakCard({required this.peak, required this.onTap});
  final Peak peak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.landscape)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(peak.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text([peak.province, peak.county, peak.mountainRange].whereType<String>().where((e) => e.trim().isNotEmpty).join(' • ')),
                  const SizedBox(height: 4),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    if (peak.elevation != null) Text('تابلو ${peak.elevation}m'),
                    if (peak.mapElevation != null) Text('Map ${peak.mapElevation}m'),
                    if (peak.hasCoordinates) const Icon(Icons.pin_drop, size: 16),
                    if (peak.dataQualityStatus != 'complete') Icon(Icons.warning_amber_rounded, size: 16, color: Theme.of(context).colorScheme.tertiary),
                  ]),
                ]),
              ),
              if (peak.favorite) const Icon(Icons.favorite, color: Colors.redAccent),
              const Icon(Icons.chevron_left),
            ]),
          ),
        ),
      );
}
