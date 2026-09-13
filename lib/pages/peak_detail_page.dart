import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../models/gpx_route.dart';
import '../models/peak.dart';
import '../services/map_links.dart';
import 'audit_history_page.dart';
import 'owner_edit_page.dart';
import 'route_edit_page.dart';

class PeakDetailPage extends StatefulWidget {
  const PeakDetailPage({super.key, required this.peak});
  final Peak peak;

  @override
  State<PeakDetailPage> createState() => _PeakDetailPageState();
}

class _PeakDetailPageState extends State<PeakDetailPage> {
  late Peak _peak = widget.peak;
  late bool _favorite = widget.peak.favorite;
  List<GpxRoute> _routes = const [];
  bool _loadingRoutes = true;

  bool get _canManage => SessionStore.instance.canManageReferenceData;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _reload() async {
    final fresh = await PeakRepository.instance.getById(_peak.id);
    if (fresh != null && mounted) {
      setState(() {
        _peak = fresh;
        _favorite = fresh.favorite;
      });
    }
    await _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final routes = await PeakRepository.instance.routesForPeak(_peak.id);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loadingRoutes = false;
    });
  }

  Future<void> _toggleFavorite() async {
    await PeakRepository.instance.toggleFavorite(_peak);
    await _reload();
  }

  Future<void> _openSummitMap() async {
    if (!_peak.hasCoordinates) return;
    final uri = MapLinks.organicMaps(
      latitude: _peak.latitude!,
      longitude: _peak.longitude!,
      name: _peak.name,
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openTrailheadMap(GpxRoute route) async {
    if (route.trailheadLatitude == null || route.trailheadLongitude == null) return;
    final uri = MapLinks.organicMaps(
      latitude: route.trailheadLatitude!,
      longitude: route.trailheadLongitude!,
      name: '${_peak.name} - ابتدای پاکوب ${route.name}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _editOwner() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OwnerEditPage(peak: _peak)),
    );
    if (changed == true) await _reload();
  }

  Future<void> _addRoute() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RouteEditPage(peakId: _peak.id)),
    );
    if (changed == true) await _loadRoutes();
  }

  Future<void> _editRoute(GpxRoute route) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RouteEditPage(peakId: _peak.id, route: route)),
    );
    if (changed == true) await _loadRoutes();
  }

  Future<void> _deleteRoute(GpxRoute route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف مسیر'),
        content: Text('مسیر «${route.name}» به‌صورت Soft Delete حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await PeakRepository.instance.softDeleteRoute(route);
      await _loadRoutes();
    }
  }

  Future<void> _deletePeak() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف قله'),
        content: Text(
          'قله «${_peak.name}» و مسیرهای آن به‌صورت Soft Delete حذف شوند؟ '
          'اطلاعات برای بازیابی آینده در بانک باقی می‌ماند.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف نرم')),
        ],
      ),
    );
    if (ok == true) {
      await PeakRepository.instance.softDeletePeak(_peak.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  Future<void> _requestAccess(GpxRoute route) async {
    final result = await PeakRepository.instance.requestRouteAccess(route);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _peak;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (_canManage)
            IconButton(onPressed: _editOwner, icon: const Icon(Icons.edit_note), tooltip: 'ویرایش قله'),
          if (_canManage)
            IconButton(onPressed: _deletePeak, icon: const Icon(Icons.delete_outline), tooltip: 'حذف نرم'),
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border,
                color: _favorite ? Colors.redAccent : null),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF176B52), Color(0xFF4F9E71)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(children: [
              const Icon(Icons.terrain, color: Colors.white, size: 64),
              Text(
                p.name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              Text(
                p.elevation == null ? 'ارتفاع تابلو ثبت نشده' : 'تابلو: ${p.elevation} متر',
                style: const TextStyle(color: Colors.white70, fontSize: 17),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (!p.isComplete) _qualityBanner(p),
          _Section(title: 'مشخصات', children: [
            _row('شناسه', p.id),
            _row('استان', p.province),
            _row('شهرستان', p.county),
            _row('بخش/دهستان', p.district),
            _row('رشته‌کوه', p.mountainRange),
            _row('نام‌های دیگر', p.aliases),
            _row('نام محلی', p.localAlias),
            _row('ارتفاع قله (تابلو)', _m(p.elevation)),
            _row('ارتفاع قله (Map)', _m(p.mapElevation)),
            _row('ارتفاع‌های گزارش‌شده', p.reportedElevations),
          ]),
          _descriptionSection(p.description),
          _Section(title: 'موقعیت جغرافیایی قله', children: [
            _row(
              'مختصات قله',
              p.hasCoordinates ? '${p.latitude!.toStringAsFixed(6)}, ${p.longitude!.toStringAsFixed(6)}' : null,
            ),
            _row('منبع مختصات', p.coordinateSource),
            if (p.hasCoordinates)
              OutlinedButton.icon(
                onPressed: _openSummitMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('باز کردن قله در Organic Maps'),
              ),
          ]),
          _routesSection(),
          _Section(title: 'اطلاعات Legacy مسیر', children: [
            _row('مسیر اصلی', p.route),
            _row('نام نقطه شروع', p.trailhead),
            _row('ارتفاع نقطه شروع', _m(p.trailheadElevationM)),
            _row('ارتفاع‌گیری', _m(p.elevationGainM)),
            _row('طول مسیر', p.routeLengthKm == null ? null : '${p.routeLengthKm} کیلومتر'),
            _row('زمان صعود', p.ascentTime),
            _row('زمان رفت‌وبرگشت', p.roundtripTime),
            _row('درجه سختی', p.difficulty),
            _row('بهترین فصل', p.bestSeason),
            _row('نیاز به راهنما', p.guideRequired),
            _row('وضعیت مسیر', p.routeStatus),
            _row('تعداد مسیرهای اعلام‌شده', '${p.routeCount}'),
          ]),
          _Section(title: 'اعتبار و منبع', children: [
            _row('وضعیت اعتبارسنجی', p.status),
            _row('کیفیت داده', _qualityLabel(p.dataQualityStatus)),
            _row('پرچم‌های داده', p.dataFlags?.replaceAll(',', '، ')),
            _row('کد منبع', p.source),
            _row('تعداد رخداد منبع', p.sourceOccurrenceCount?.toString()),
            _row('آخرین ویرایش جلالی', p.updatedAtJalali),
            if (p.sourceUrl != null && p.sourceUrl!.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(p.sourceUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('بازکردن لینک منبع'),
              ),
            if (_canManage)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AuditHistoryPage(peakId: p.id, peakName: p.name)),
                ),
                icon: const Icon(Icons.history),
                label: const Text('تاریخچه تغییرات'),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _qualityBanner(Peak p) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: Icon(p.needsReview ? Icons.report_problem_outlined : Icons.info_outline),
          title: Text(p.needsReview ? 'این رکورد نیازمند بررسی است' : 'اطلاعات این قله هنوز کامل نیست'),
          subtitle: Text(p.dataFlags?.replaceAll(',', '، ') ?? 'برخی فیلدها تکمیل نشده‌اند.'),
        ),
      );

  Widget _descriptionSection(String? description) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('توضیحات کامل', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const Divider(),
            Container(
              constraints: const BoxConstraints(minHeight: 90, maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  description == null || description.trim().isEmpty ? 'توضیحی ثبت نشده است.' : description,
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _routesSection() => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(
                child: Text('مسیرهای GPX', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              if (_canManage)
                FilledButton.tonalIcon(onPressed: _addRoute, icon: const Icon(Icons.add), label: const Text('مسیر')),
            ]),
            const Divider(),
            if (_loadingRoutes)
              const Center(child: CircularProgressIndicator())
            else if (_routes.isEmpty)
              const Text('برای این قله هنوز مسیر GPX ثبت نشده است.')
            else
              for (final route in _routes) _routeCard(route),
          ]),
        ),
      );

  Widget _routeCard(GpxRoute route) {
    final hasTrailheadCoordinates = route.trailheadLatitude != null && route.trailheadLongitude != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(route.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (_canManage)
            IconButton(onPressed: () => _editRoute(route), icon: const Icon(Icons.edit_outlined), tooltip: 'ویرایش مسیر'),
          if (_canManage)
            IconButton(onPressed: () => _deleteRoute(route), icon: const Icon(Icons.delete_outline), tooltip: 'حذف نرم مسیر'),
        ]),
        Wrap(spacing: 12, runSpacing: 6, children: [
          Text(route.routeLengthKm == null ? 'طول: —' : 'طول: ${route.routeLengthKm} km'),
          Text(route.elevationGainM == null ? 'ارتفاع‌گیری: —' : 'ارتفاع‌گیری: ${route.elevationGainM} m'),
          Text('دانلود: ${route.downloadCount}'),
        ]),
        const SizedBox(height: 6),
        Text('ابتدای پاکوب: ${route.trailhead ?? 'ثبت نشده'}'),
        Text(
          hasTrailheadCoordinates
              ? 'مختصات پاکوب: ${route.trailheadLatitude!.toStringAsFixed(6)}, ${route.trailheadLongitude!.toStringAsFixed(6)}'
              : 'مختصات پاکوب: ثبت نشده',
        ),
        if (route.trailheadElevationM != null) Text('ارتفاع ابتدای پاکوب: ${route.trailheadElevationM} متر'),
        if (hasTrailheadCoordinates)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: () => _openTrailheadMap(route),
              icon: const Icon(Icons.directions_walk),
              label: const Text('باز کردن ابتدای مسیر در Organic Maps'),
            ),
          ),
        Text('منبع/مالک: ${route.sourceOwner ?? 'ثبت نشده'}'),
        Text('وضعیت: ${_publicationLabel(route.publicationStatus)}'),
        if (route.dataFlags?.isNotEmpty ?? false) Text('نیاز به تکمیل: ${route.dataFlags!.replaceAll(',', '، ')}'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              route.isFree ? 'رایگان' : '${_formatPrice(route.priceIrr)} ریال',
              style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _requestAccess(route),
            icon: Icon(route.isFree ? Icons.download : Icons.shopping_cart_checkout),
            label: Text(route.isFree ? 'دریافت GPX' : 'خرید GPX'),
          ),
        ]),
      ]),
    );
  }

  String _formatPrice(int value) {
    final raw = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
      out.write(raw[i]);
    }
    return out.toString();
  }

  String _publicationLabel(String value) => switch (value) {
        'published' => 'منتشرشده',
        'archived' => 'آرشیو',
        _ => 'پیش‌نویس',
      };

  String _qualityLabel(String value) => switch (value) {
        'complete' => 'کامل',
        'needs_review' => 'نیازمند بررسی',
        _ => 'ناقص',
      };

  String? _m(int? value) => value == null ? null : '$value متر';

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 150,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value == null || value.trim().isEmpty ? 'ثبت نشده' : value)),
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const Divider(),
            ...children,
          ]),
        ),
      );
}
