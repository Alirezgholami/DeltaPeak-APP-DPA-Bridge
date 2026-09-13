import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/peak_repository.dart';
import '../models/education.dart';
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
                padding: const EdgeInsets.all(16),
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
                              '۶ بخش و ۴۲ درس کوتاه و کاربردی؛ از برنامه‌ریزی و تجهیزات تا GPX، هواشناسی و کمک‌های اولیه.',
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
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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

class EducationContentPage extends StatelessWidget {
  const EducationContentPage({super.key, required this.content});
  final EducationContent content;

  List<Uri> get _links => RegExp(r'https?://[^\s]+')
      .allMatches(content.body)
      .map((m) => Uri.tryParse(m.group(0)!))
      .whereType<Uri>()
      .toList(growable: false);

  Future<void> _openLink(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('باز کردن لینک ممکن نشد.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    return Scaffold(
      appBar: AppBar(title: const Text('آموزش')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(content.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            SelectableText(content.body, style: const TextStyle(height: 1.9, fontSize: 16)),
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
                    onPressed: () => _openLink(context, uri),
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
}
