import 'package:flutter/material.dart';
import '../data/peak_repository.dart';
import '../models/peak.dart';
import '../utils/persian_normalizer.dart';
import '../utils/persian_input_formatters.dart';

class OwnerEditPage extends StatefulWidget {
  const OwnerEditPage({super.key, this.peak});
  final Peak? peak;

  @override
  State<OwnerEditPage> createState() => _OwnerEditPageState();
}

class _OwnerEditPageState extends State<OwnerEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _province;
  final FocusNode _mountainRangeFocusNode = FocusNode();
  List<String> _mountainRanges = const [];
  bool _saving = false;
  bool get _isNew => widget.peak == null;

  @override
  void initState() {
    super.initState();
    final p = widget.peak;
    _province = p?.province ?? PeakRepository.officialProvinceOrder.first;
    _c = {
      'name': TextEditingController(text: p?.name ?? ''),
      'aliases': TextEditingController(text: p?.aliases ?? ''),
      'localAlias': TextEditingController(text: p?.localAlias ?? ''),
      'mountainRange': TextEditingController(text: p?.mountainRange ?? ''),
      'description': TextEditingController(text: p?.description ?? ''),
      'elevation': TextEditingController(text: p?.elevation?.toString() ?? ''),
      'mapElevation': TextEditingController(text: p?.mapElevation?.toString() ?? ''),
      'reportedElevations': TextEditingController(text: p?.reportedElevations ?? ''),
      'county': TextEditingController(text: p?.county ?? ''),
      'district': TextEditingController(text: p?.district ?? ''),
      'latitude': TextEditingController(text: p?.latitude?.toString() ?? ''),
      'longitude': TextEditingController(text: p?.longitude?.toString() ?? ''),
      'coordinateSource': TextEditingController(text: p?.coordinateSource ?? ''),
      'route': TextEditingController(text: p?.route ?? ''),
      'trailhead': TextEditingController(text: p?.trailhead ?? ''),
      'trailheadElevationM': TextEditingController(text: p?.trailheadElevationM?.toString() ?? ''),
      'elevationGainM': TextEditingController(text: p?.elevationGainM?.toString() ?? ''),
      'routeLengthKm': TextEditingController(text: p?.routeLengthKm?.toString() ?? ''),
      'ascentTime': TextEditingController(text: p?.ascentTime ?? ''),
      'roundtripTime': TextEditingController(text: p?.roundtripTime ?? ''),
      'difficulty': TextEditingController(text: p?.difficulty ?? ''),
      'bestSeason': TextEditingController(text: p?.bestSeason ?? ''),
      'guideRequired': TextEditingController(text: p?.guideRequired ?? ''),
      'routeStatus': TextEditingController(text: p?.routeStatus ?? ''),
      'routeCount': TextEditingController(text: (p?.routeCount ?? 0).toString()),
      'status': TextEditingController(text: p?.status ?? ''),
      'source': TextEditingController(text: p?.source ?? ''),
      'sourceOccurrenceCount': TextEditingController(text: p?.sourceOccurrenceCount?.toString() ?? ''),
      'sourceUrl': TextEditingController(text: p?.sourceUrl ?? ''),
      'rawTextSample': TextEditingController(text: p?.rawTextSample ?? ''),
    };
    _loadMountainRanges();
  }

  Future<void> _loadMountainRanges() async {
    final values = await PeakRepository.instance.mountainRangeNames();
    if (!mounted) return;
    setState(() => _mountainRanges = values);
  }

  @override
  void dispose() {
    for (final controller in _c.values) {
      controller.dispose();
    }
    _mountainRangeFocusNode.dispose();
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

  Peak _formPeak() {
    final old = widget.peak;
    return Peak(
      id: old?.id ?? '',
      name: PersianNormalizer.normalizeText(_c['name']!.text),
      province: _province,
      aliases: _text('aliases'),
      localAlias: _text('localAlias'),
      mountainRange: _text('mountainRange'),
      description: _text('description'),
      elevation: _int('elevation'),
      mapElevation: _int('mapElevation'),
      reportedElevations: _text('reportedElevations'),
      sourceOccurrenceCount: _int('sourceOccurrenceCount'),
      county: _text('county'),
      district: _text('district'),
      latitude: _double('latitude'),
      longitude: _double('longitude'),
      coordinateSource: _text('coordinateSource'),
      route: _text('route'),
      trailhead: _text('trailhead'),
      trailheadElevationM: _int('trailheadElevationM'),
      elevationGainM: _int('elevationGainM'),
      routeLengthKm: _double('routeLengthKm'),
      ascentTime: _text('ascentTime'),
      roundtripTime: _text('roundtripTime'),
      difficulty: _text('difficulty'),
      bestSeason: _text('bestSeason'),
      guideRequired: _text('guideRequired'),
      routeStatus: _text('routeStatus'),
      routeCount: _int('routeCount') ?? 0,
      status: _text('status'),
      source: _rawText('source'),
      rawTextSample: _rawText('rawTextSample'),
      sourceUrl: _rawText('sourceUrl'),
      favorite: old?.favorite ?? false,
      updatedAtJalali: old?.updatedAtJalali,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final peak = _formPeak();
      if (_isNew) {
        await PeakRepository.instance.addPeak(peak);
      } else {
        await PeakRepository.instance.updatePeak(peak);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره ناموفق بود: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'افزودن قله' : 'ویرایش قله'),
          actions: [
            IconButton(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), tooltip: 'ذخیره'),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _isNew
                      ? 'قله جدید به بانک محلی افزوده و در Audit Log ثبت می‌شود.'
                      : 'ویرایش‌ها در بانک محلی و Audit Log با تاریخ جلالی ثبت می‌شوند.',
                ),
              ),
              const SizedBox(height: 12),
              if (!_isNew) _readOnly('شناسه داخلی', widget.peak!.id),
              _field('نام قله', 'name', required: true),
              _provinceField(),
              _mountainRangeField(),
              _field('توضیحات کامل', 'description', long: true, maxLines: 10),
              _field('شهرستان', 'county'),
              _field('بخش/دهستان', 'district'),
              _field('نام‌های مرتبط', 'aliases'),
              _field('نام محلی/مستعار', 'localAlias'),
              _field('ارتفاع قله (تابلو)', 'elevation', number: true),
              _field('ارتفاع قله (Map)', 'mapElevation', number: true),
              _field('ارتفاع‌های گزارش‌شده', 'reportedElevations'),
              const Divider(height: 28),
              _field('عرض جغرافیایی', 'latitude', decimal: true),
              _field('طول جغرافیایی', 'longitude', decimal: true),
              _field('منبع مختصات', 'coordinateSource', long: true),
              const Divider(height: 28),
              _field('مسیر اصلی صعود (Legacy)', 'route', long: true),
              _field('نقطه شروع مسیر', 'trailhead', long: true),
              _field('ارتفاع نقطه شروع (متر)', 'trailheadElevationM', number: true),
              _field('ارتفاع‌گیری (متر)', 'elevationGainM', number: true),
              _field('طول مسیر (کیلومتر)', 'routeLengthKm', decimal: true),
              _field('زمان صعود', 'ascentTime'),
              _field('زمان رفت‌وبرگشت', 'roundtripTime'),
              _field('درجه سختی', 'difficulty'),
              _field('بهترین فصل صعود', 'bestSeason'),
              _field('نیاز به راهنما', 'guideRequired'),
              _field('وضعیت مسیر', 'routeStatus', long: true),
              _field('تعداد مسیرها در منبع', 'routeCount', number: true),
              const Divider(height: 28),
              _field('وضعیت اعتبارسنجی', 'status', long: true),
              _field('کدهای منبع', 'source', normalizeInput: false),
              _field('تعداد رخداد در منبع', 'sourceOccurrenceCount', number: true),
              _field('لینک منبع', 'sourceUrl', long: true, normalizeInput: false),
              _field('نمونه متن خام', 'rawTextSample', long: true, maxLines: 7, normalizeInput: false),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_isNew ? 'افزودن قله' : 'ذخیره تغییرات'),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      );

  Widget _provinceField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<String>(
          initialValue: _province,
          items: PeakRepository.officialProvinceOrder
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (value) => setState(() => _province = value ?? _province),
          decoration: const InputDecoration(labelText: 'استان'),
        ),
      );

  Iterable<String> _mountainRangeOptions(TextEditingValue value) {
    final query = PersianNormalizer.normalizeSearch(value.text);
    if (query.isEmpty) return const Iterable<String>.empty();
    final starts = <String>[];
    final contains = <String>[];
    for (final range in _mountainRanges) {
      final normalized = PersianNormalizer.normalizeSearch(range);
      if (normalized.startsWith(query)) {
        starts.add(range);
      } else if (normalized.contains(query)) {
        contains.add(range);
      }
    }
    return [...starts, ...contains].take(10);
  }

  Widget _mountainRangeField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RawAutocomplete<String>(
          textEditingController: _c['mountainRange'],
          focusNode: _mountainRangeFocusNode,
          displayStringForOption: (option) => option,
          optionsBuilder: _mountainRangeOptions,
          onSelected: (value) {
            _c['mountainRange']!.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
              TextFormField(
            controller: controller,
            focusNode: focusNode,
            inputFormatters: const [PersianTextInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'رشته‌کوه',
              helperText: 'از اولین حرف پیشنهاد می‌شود؛ نام جدید بعد از ذخیره به فهرست افزوده می‌شود.',
            ),
            onFieldSubmitted: (_) => onFieldSubmitted(),
          ),
          optionsViewBuilder: (context, onSelected, options) {
            final values = options.toList(growable: false);
            return Align(
              alignment: Alignment.topRight,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 260,
                    maxWidth: MediaQuery.sizeOf(context).width - 32,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: values.length,
                    itemBuilder: (context, index) => ListTile(
                      dense: true,
                      title: Text(values[index]),
                      onTap: () => onSelected(values[index]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _readOnly(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InputDecorator(decoration: InputDecoration(labelText: label), child: SelectableText(value)),
      );

  Widget _field(
    String label,
    String key, {
    bool required = false,
    bool number = false,
    bool decimal = false,
    bool long = false,
    bool normalizeInput = true,
    int? maxLines,
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
          maxLines: maxLines ?? (long ? 5 : 1),
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
