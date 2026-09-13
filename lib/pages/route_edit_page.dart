import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/peak_repository.dart';
import '../models/gpx_route.dart';
import '../utils/persian_normalizer.dart';
import '../utils/persian_input_formatters.dart';

class RouteEditPage extends StatefulWidget {
  const RouteEditPage({super.key, required this.peakId, this.route});
  final String peakId;
  final GpxRoute? route;

  @override
  State<RouteEditPage> createState() => _RouteEditPageState();
}

class _RouteEditPageState extends State<RouteEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _publicationStatus;
  String? _gpxPath;
  String? _gpxSha256;
  bool _saving = false;
  bool _importingGpx = false;

  bool get _isNew => widget.route == null;

  @override
  void initState() {
    super.initState();
    final r = widget.route;
    _publicationStatus = r?.publicationStatus ?? 'draft';
    _gpxPath = r?.gpxFilePath;
    _gpxSha256 = r?.fileSha256;
    _c = {
      'name': TextEditingController(text: r?.name ?? ''),
      'routeLengthKm': TextEditingController(text: r?.routeLengthKm?.toString() ?? ''),
      'elevationGainM': TextEditingController(text: r?.elevationGainM?.toString() ?? ''),
      'trailhead': TextEditingController(text: r?.trailhead ?? ''),
      'trailheadLatitude': TextEditingController(text: r?.trailheadLatitude?.toString() ?? ''),
      'trailheadLongitude': TextEditingController(text: r?.trailheadLongitude?.toString() ?? ''),
      'trailheadElevationM': TextEditingController(text: r?.trailheadElevationM?.toString() ?? ''),
      'sourceOwner': TextEditingController(text: r?.sourceOwner ?? ''),
      'sourceUrl': TextEditingController(text: r?.sourceUrl ?? ''),
      'priceIrr': TextEditingController(text: (r?.priceIrr ?? 0).toString()),
      'difficulty': TextEditingController(text: r?.difficulty ?? ''),
      'estimatedDuration': TextEditingController(text: r?.estimatedDuration ?? ''),
      'bestSeason': TextEditingController(text: r?.bestSeason ?? ''),
      'routeType': TextEditingController(text: r?.routeType ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(String key) =>
      PersianNormalizer.normalizeNullableText(_c[key]!.text);

  String? _rawText(String key) {
    final value = _c[key]!.text.trim();
    return value.isEmpty ? null : value;
  }

  int? _int(String key) =>
      int.tryParse(PersianNormalizer.normalizeNumberInput(_c[key]!.text));

  double? _double(String key) =>
      double.tryParse(PersianNormalizer.normalizeNumberInput(_c[key]!.text));

  Future<void> _pickGpx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() => _importingGpx = true);
    try {
      final stored = await PeakRepository.instance.importGpxFile(
        result.files.single.path!,
        currentRouteId: widget.route?.routeId,
      );
      if (!mounted) return;
      setState(() {
        _gpxPath = stored.path;
        _gpxSha256 = stored.sha256;
        _importingGpx = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingGpx = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ورود GPX ناموفق بود: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = _int('priceIrr') ?? 0;
    if (price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('قیمت نمی‌تواند منفی باشد.')));
      return;
    }
    setState(() => _saving = true);
    final old = widget.route;
    final route = GpxRoute(
      routeId: old?.routeId ?? '',
      peakId: widget.peakId,
      name: PersianNormalizer.normalizeText(_c['name']!.text),
      gpxFilePath: _gpxPath,
      routeLengthKm: _double('routeLengthKm'),
      elevationGainM: _int('elevationGainM'),
      trailhead: _text('trailhead'),
      trailheadLatitude: _double('trailheadLatitude'),
      trailheadLongitude: _double('trailheadLongitude'),
      trailheadElevationM: _int('trailheadElevationM'),
      sourceOwner: _text('sourceOwner'),
      sourceUrl: _rawText('sourceUrl'),
      priceIrr: price,
      currency: 'IRR',
      publicationStatus: _publicationStatus,
      downloadCount: old?.downloadCount ?? 0,
      routeCountHint: old?.routeCountHint ?? 1,
      difficulty: _text('difficulty'),
      estimatedDuration: _text('estimatedDuration'),
      bestSeason: _text('bestSeason'),
      routeType: _text('routeType'),
      fileSha256: _gpxSha256,
      version: old?.version ?? 1,
    );
    try {
      await PeakRepository.instance.saveRoute(route);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره مسیر ناموفق بود: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'افزودن مسیر GPX' : 'ویرایش مسیر GPX'),
          actions: [
            IconButton(
              onPressed: _saving || _importingGpx ? null : _save,
              icon: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              tooltip: 'ذخیره',
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _field('نام مسیر', 'name', required: true),
              _field('طول مسیر (کیلومتر)', 'routeLengthKm', decimal: true),
              _field('ارتفاع‌گیری (متر)', 'elevationGainM', number: true),
              const Divider(height: 28),
              const Text('ابتدای پاکوب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              _field('نام / توضیح ابتدای پاکوب', 'trailhead', long: true),
              _field('عرض جغرافیایی ابتدای پاکوب', 'trailheadLatitude', decimal: true),
              _field('طول جغرافیایی ابتدای پاکوب', 'trailheadLongitude', decimal: true),
              _field('ارتفاع ابتدای پاکوب (متر)', 'trailheadElevationM', number: true),
              const Divider(height: 28),
              _field('منبع / مالک مسیر', 'sourceOwner'),
              _field('لینک منبع', 'sourceUrl', long: true, normalizeInput: false),
              _field('قیمت دانلود (ریال)', 'priceIrr', number: true),
              _field('درجه سختی', 'difficulty'),
              _field('زمان تقریبی', 'estimatedDuration'),
              _field('بهترین فصل', 'bestSeason'),
              _field('نوع مسیر', 'routeType'),
              DropdownButtonFormField<String>(
                initialValue: _publicationStatus,
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('پیش‌نویس')),
                  DropdownMenuItem(value: 'published', child: Text('منتشرشده')),
                  DropdownMenuItem(value: 'archived', child: Text('آرشیو')),
                ],
                onChanged: (v) => setState(() => _publicationStatus = v ?? 'draft'),
                decoration: const InputDecoration(labelText: 'وضعیت انتشار'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _importingGpx ? null : _pickGpx,
                icon: _importingGpx
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_gpxPath == null ? 'انتخاب و ثبت امن فایل GPX' : 'GPX: ${_gpxPath!.split('/').last}'),
              ),
              if (_gpxSha256 != null) ...[
                const SizedBox(height: 6),
                SelectableText('SHA-256: $_gpxSha256', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 18),
              const Text('برای ذخیره، آیکون دیسکت بالای صفحه را بزنید.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _field(
    String label,
    String key, {
    bool required = false,
    bool number = false,
    bool decimal = false,
    bool long = false,
    bool normalizeInput = true,
  }) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _c[key],
          inputFormatters: !normalizeInput
              ? const []
              : (number || decimal
                  ? const [LocalizedNumberInputFormatter()]
                  : const [PersianTextInputFormatter()]),
          keyboardType: number || decimal
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : TextInputType.multiline,
          minLines: long ? 2 : 1,
          maxLines: long ? 4 : 1,
          validator: (value) {
            final text = PersianNormalizer.normalizeText(value);
            if (required && text.isEmpty) return 'این فیلد الزامی است.';
            if (text.isEmpty || !(number || decimal)) return null;
            final numeric = PersianNormalizer.normalizeNumberInput(value);
            final valid = decimal
                ? double.tryParse(numeric) != null
                : int.tryParse(numeric) != null;
            return valid ? null : 'عدد معتبر وارد کنید.';
          },
          decoration: InputDecoration(labelText: label),
        ),
      );
}
