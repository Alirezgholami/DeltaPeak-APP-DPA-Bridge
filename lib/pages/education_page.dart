import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_store.dart';
import '../data/peak_repository.dart';
import '../models/education.dart';
import '../models/education_media.dart';
import '../services/education_media_store.dart';
import '../utils/persian_normalizer.dart';

class EducationPage extends StatefulWidget {
  const EducationPage({super.key});

  @override
  State<EducationPage> createState() => _EducationPageState();
}

class _EducationPageState extends State<EducationPage> {
  static const _descriptions = <String, String>{
    'EDU-CAT-01': 'برنامه‌ریزی، ریتم حرکت، آب و تغذیه و اصول گروه‌روی',
    'EDU-CAT-02': 'کفش، پوشاک، کوله، روشنایی و تجهیزات متناسب با برنامه',
    'EDU-CAT-03': 'GPX، نقشه آفلاین، AlpineQuest، GPS و مسیرهای DPA',
    'EDU-CAT-04': 'مدیریت ریسک، زمان برگشت، گم‌شدن و شرایط اضطراری',
    'EDU-CAT-05': 'باد، دما، بارش، مه، رعدوبرق و تصمیم‌گیری جوی',
    'EDU-CAT-06': 'اصول اولیه برخورد با آسیب‌ها تا رسیدن کمک تخصصی',
  };

  List<EducationCategory> _categories = const [];
  bool _loading = true;

  IconData _icon(String id) => switch (id) {
        'EDU-CAT-01' => Icons.hiking,
        'EDU-CAT-02' => Icons.backpack_outlined,
        'EDU-CAT-03' => Icons.route_outlined,
        'EDU-CAT-04' => Icons.health_and_safety_outlined,
        'EDU-CAT-05' => Icons.cloud_outlined,
        'EDU-CAT-06' => Icons.medical_services_outlined,
        _ => Icons.school_outlined,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PeakRepository.instance.educationCategories();
    if (!mounted) return;
    setState(() {
      _categories = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('آموزش')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: _categories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'دانش کاربردی برای برنامه ایمن‌تر',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'آموزش‌های DPA می‌توانند علاوه بر متن، تصویر و پیوند مدیا داشته باشند.',
                              style: TextStyle(height: 1.7),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final item = _categories[index - 1];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(child: Icon(_icon(item.categoryId))),
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(_descriptions[item.categoryId] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EducationCategoryPage(category: item)),
                      ),
                    ),
                  );
                },
              ),
      );
}

class EducationCategoryPage extends StatefulWidget {
  const EducationCategoryPage({super.key, required this.category});
  final EducationCategory category;

  @override
  State<EducationCategoryPage> createState() => _EducationCategoryPageState();
}

class _EducationCategoryPageState extends State<EducationCategoryPage> {
  final _searchController = TextEditingController();
  List<EducationContent> _contents = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await PeakRepository.instance.educationContents(widget.category.categoryId);
    if (!mounted) return;
    setState(() {
      _contents = items;
      _loading = false;
    });
  }

  List<EducationContent> get _filtered {
    final q = PersianNormalizer.normalizeSearch(_query);
    if (q.isEmpty) return _contents;
    return _contents.where((item) {
      final haystack = PersianNormalizer.normalizeSearch('${item.title} ${item.body}');
      return haystack.contains(q);
    }).toList();
  }

  String _preview(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 130 ? compact : '${compact.substring(0, 130)}…';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'جست‌وجو در آموزش‌های این بخش…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('${visible.length} درس', style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('مطلبی با این عبارت پیدا نشد.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final content = visible[index];
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Text(content.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(_preview(content.body), style: const TextStyle(height: 1.6)),
                                ),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => EducationContentPage(content: content)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class EducationContentPage extends StatefulWidget {
  const EducationContentPage({super.key, required this.content});
  final EducationContent content;

  @override
  State<EducationContentPage> createState() => _EducationContentPageState();
}

class _EducationContentPageState extends State<EducationContentPage> {
  List<EducationMedia> _media = const [];
  bool _loadingMedia = true;
  bool _busy = false;

  bool get _canManage => SessionStore.instance.canManageReferenceData;

  List<Uri> get _links => RegExp(r'https?://[^\s]+')
      .allMatches(widget.content.body)
      .map((m) => Uri.tryParse(m.group(0)!))
      .whereType<Uri>()
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final media = await EducationMediaStore.instance.listForContent(widget.content.contentId);
    if (!mounted) return;
    setState(() {
      _media = media;
      _loadingMedia = false;
    });
  }

  Future<void> _openLink(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('باز کردن لینک ممکن نشد.')));
    }
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    final caption = await _captionDialog('توضیح تصویر');
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final ext = (file!.extension ?? 'jpg').toLowerCase();
      final mime = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      await EducationMediaStore.instance.addImage(
        contentId: widget.content.contentId,
        bytes: file.bytes!,
        mimeType: mime,
        caption: caption,
      );
      await _loadMedia();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMediaLink() async {
    final values = await _mediaLinkDialog();
    if (values == null) return;
    setState(() => _busy = true);
    try {
      await EducationMediaStore.instance.addMediaLink(
        contentId: widget.content.contentId,
        url: values.$1,
        caption: values.$2,
      );
      await _loadMedia();
    } on FormatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMedia(EducationMedia item) async {
    await EducationMediaStore.instance.delete(item.mediaId);
    await _loadMedia();
  }

  Future<String?> _captionDialog(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیح / Caption')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بدون توضیح')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('تأیید')),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<(String, String?)?> _mediaLinkDialog() async {
    final url = TextEditingController();
    final caption = TextEditingController();
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('افزودن مدیا'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'لینک ویدئو / صوت / مدیا')),
            const SizedBox(height: 10),
            TextField(controller: caption, decoration: const InputDecoration(labelText: 'عنوان یا توضیح')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final u = url.text.trim();
              if (u.isEmpty) return;
              final c = caption.text.trim();
              Navigator.pop(context, (u, c.isEmpty ? null : c));
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
    url.dispose();
    caption.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    return Scaffold(
      appBar: AppBar(
        title: const Text('آموزش'),
        actions: [
          if (_canManage)
            PopupMenuButton<String>(
              enabled: !_busy,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'افزودن عکس یا مدیا',
              onSelected: (value) => value == 'image' ? _addImage() : _addMediaLink(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('افزودن تصویر'))),
                PopupMenuItem(value: 'media', child: ListTile(leading: Icon(Icons.perm_media_outlined), title: Text('افزودن لینک مدیا'))),
              ],
            ),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(widget.content.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            SelectableText(widget.content.body, style: const TextStyle(height: 1.9, fontSize: 16)),
            if (_loadingMedia) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ] else if (_media.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Divider(),
              Text('تصاویر و مدیا', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final item in _media) _mediaCard(item),
            ],
            if (links.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text('پیوندهای این آموزش', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final uri in links)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openLink(uri),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(uri.host.isEmpty ? uri.toString() : uri.host),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mediaCard(EducationMedia item) {
    final caption = item.caption?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.isImage && item.bytes != null)
            Image.memory(item.bytes!, fit: BoxFit.contain)
          else if (item.url != null)
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: Text(caption?.isNotEmpty == true ? caption! : 'باز کردن مدیا'),
              subtitle: Text(item.url!, textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                final uri = Uri.tryParse(item.url!);
                if (uri != null) _openLink(uri);
              },
            ),
          if (item.isImage && caption?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(caption!),
            ),
          if (_canManage)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: 'حذف مدیا',
                onPressed: _busy ? null : () => _deleteMedia(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    );
  }
}
