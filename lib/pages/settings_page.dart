import 'package:flutter/material.dart';
import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../theme/app_theme_controller.dart';
import 'account_page.dart';
import 'data_safety_page.dart';
import 'education_management_page.dart';
import 'favorites_page.dart';
import 'stats_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _coordinatesKey = 'home_filter_coordinates';
  static const _gpxKey = 'home_filter_gpx';
  static const _qualityKey = 'home_filter_quality';

  bool _coordinatesOnly = false;
  bool _gpxOnly = false;
  String? _quality;
  bool _filtersLoading = true;

  @override
  void initState() {
    super.initState();
    SessionStore.instance.addListener(_sessionChanged);
    _loadFilters();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionStore.instance.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _loadFilters() async {
    final repo = PeakRepository.instance;
    final values = await Future.wait<String?>([
      repo.getSetting(_coordinatesKey),
      repo.getSetting(_gpxKey),
      repo.getSetting(_qualityKey),
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
      _filtersLoading = false;
    });
  }

  Future<void> _setCoordinates(bool value) async {
    setState(() => _coordinatesOnly = value);
    await PeakRepository.instance.setSetting(_coordinatesKey, value ? '1' : null);
  }

  Future<void> _setGpx(bool value) async {
    setState(() => _gpxOnly = value);
    await PeakRepository.instance.setSetting(_gpxKey, value ? '1' : null);
  }

  Future<void> _toggleQuality(String value) async {
    final next = _quality == value ? null : value;
    setState(() => _quality = next);
    await PeakRepository.instance.setSetting(_qualityKey, next);
  }

  Future<void> _clearFilters() async {
    setState(() {
      _coordinatesOnly = false;
      _gpxOnly = false;
      _quality = null;
    });
    final repo = PeakRepository.instance;
    await Future.wait<void>([
      repo.setSetting(_coordinatesKey, null),
      repo.setSetting(_gpxKey, null),
      repo.setSetting(_qualityKey, null),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.instance;
    final canManage = SessionStore.instance.canManageReferenceData;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات DPA')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Theme', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: controller.mode, onChanged: (v) => v == null ? null : controller.setMode(v), title: const Text('سیستم / System')),
                RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: controller.mode, onChanged: (v) => v == null ? null : controller.setMode(v), title: const Text('روشن / Light')),
                RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: controller.mode, onChanged: (v) => v == null ? null : controller.setMode(v), title: const Text('تاریک / Dark')),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: _filtersLoading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('فیلترهای فهرست قله‌ها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                            ),
                            IconButton(
                              onPressed: _clearFilters,
                              tooltip: 'پاک کردن فیلترها',
                              icon: const Icon(Icons.filter_alt_off_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _chip(label: 'مختصات', selected: _coordinatesOnly, onSelected: _setCoordinates),
                              const SizedBox(width: 8),
                              _chip(label: 'GPX', selected: _gpxOnly, onSelected: _setGpx),
                              const SizedBox(width: 8),
                              _chip(label: 'ناقص', selected: _quality == 'incomplete', onSelected: (_) => _toggleQuality('incomplete')),
                              const SizedBox(width: 8),
                              _chip(label: 'نیازمند بررسی', selected: _quality == 'needs_review', onSelected: (_) => _toggleQuality('needs_review')),
                              const SizedBox(width: 8),
                              _chip(label: 'کامل', selected: _quality == 'complete', onSelected: (_) => _toggleQuality('complete')),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (canManage)
            _nav(
              context,
              Icons.school_outlined,
              'مدیریت آموزش؛ Draft / Publish / Archive',
              const EducationManagementPage(),
            ),
          _nav(context, Icons.favorite_border, 'علاقه‌مندی‌ها', const FavoritesPage()),
          _nav(context, Icons.account_circle_outlined, 'حساب کاربری', const AccountPage()),
          _nav(context, Icons.security_outlined, 'Backup / Restore / Import / Migration', const DataSafetyPage()),
          _nav(context, Icons.info_outline, 'About / Database Info', const StatsPage()),
        ],
      ),
    );
  }

  Widget _chip({required String label, required bool selected, required ValueChanged<bool> onSelected}) => FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: true,
        onSelected: onSelected,
        visualDensity: VisualDensity.compact,
      );

  Widget _nav(BuildContext context, IconData icon, String title, Widget page) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        ),
      );
}
