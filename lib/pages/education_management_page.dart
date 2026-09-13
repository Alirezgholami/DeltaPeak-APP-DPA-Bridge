import 'package:flutter/material.dart';

import '../data/peak_repository.dart';
import '../models/education.dart';
import '../services/education_content_store.dart';
import 'education_page.dart';

class EducationManagementPage extends StatefulWidget {
  const EducationManagementPage({super.key});

  @override
  State<EducationManagementPage> createState() => _EducationManagementPageState();
}

class _EducationManagementPageState extends State<EducationManagementPage> {
  List<EducationCategory> _categories = const [];
  List<ManagedEducationContent> _items = const [];
  Map<String, int> _counts = const {};
  bool _loading = true;
  String? _status;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait<dynamic>([
      PeakRepository.instance.educationCategories(),
      EducationContentStore.instance.listAll(
        categoryId: _categoryId,
        status: _status,
      ),
      EducationContentStore.instance.statusCounts(),
    ]);
    if (!mounted) return;
    setState(() {
      _categories = results[0] as List<EducationCategory>;
      _items = results[1] as List<ManagedEducationContent>;
      _counts = results[2] as Map<String, int>;
      _loading = false;
    });
  }

  String _categoryTitle(String id) => _categories
      .where((c) => c.categoryId == id)
      .map((c) => c.title)
      .cast<String?>()
      .firstOrNull ?? id;

  Future<void> _openEditor({ManagedEducationContent? item}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EducationEditorPage(
          categories: _categories,
          item: item,
          initialCategoryId: _categoryId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _setStatus(ManagedEducationContent item, String status) async {
    await EducationContentStore.instance.setStatus(item.contentId, status);
    await _load();
  }

  Future<void> _preview(ManagedEducationContent item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EducationContentPage(content: item.toEducationContent()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت آموزش'),
          actions: [
            IconButton(
              onPressed: _loading ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              tooltip: 'مطلب آموزشی جدید',
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'بازخوانی',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : () => _openEditor(),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('آموزش جدید'),
        ),
        body: Column(
          children: [
            _filters(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('مطلبی در این وضعیت وجود ندارد.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, index) => _card(_items[index]),
                          ),
                        ),
            ),
          ],
        ),
      );

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statusChip(null, 'همه'),
                  const SizedBox(width: 6),
                  _statusChip('draft', 'Draft ${_counts['draft'] ?? 0}'),
                  const SizedBox(width: 6),
                  _statusChip('published', 'Published ${_counts['published'] ?? 0}'),
                  const SizedBox(width: 6),
                  _statusChip('archived', 'Archived ${_counts['archived'] ?? 0}'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'دسته آموزشی'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('همه دسته‌ها')),
                ..._categories.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.categoryId,
                    child: Text(c.title),
                  ),
                ),
              ],
              onChanged: (value) {
                _categoryId = value;
                _load();
              },
            ),
          ],
        ),
      );

  Widget _statusChip(String? value, String label) => ChoiceChip(
        label: Text(label),
        selected: _status == value,
        onSelected: (_) {
          _status = value;
          _load();
        },
      );

  Widget _card(ManagedEducationContent item) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = switch (item.publicationStatus) {
      'published' => scheme.primaryContainer,
      'draft' => scheme.tertiaryContainer,
      _ => scheme.surfaceContainerHighest,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(_categoryTitle(item.categoryId), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(item.publicationStatus),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.body.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _preview(item),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('پیش‌نمایش'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openEditor(item: item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('ویرایش'),
                ),
                if (!item.isPublished)
                  FilledButton.icon(
                    onPressed: () => _setStatus(item, 'published'),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('تأیید نهایی / Publish'),
                  ),
                if (!item.isDraft)
                  TextButton.icon(
                    onPressed: () => _setStatus(item, 'draft'),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('برگشت به Draft'),
                  ),
                if (!item.isArchived)
                  TextButton.icon(
                    onPressed: () => _setStatus(item, 'archived'),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EducationEditorPage extends StatefulWidget {
  const EducationEditorPage({
    super.key,
    required this.categories,
    this.item,
    this.initialCategoryId,
  });

  final List<EducationCategory> categories;
  final ManagedEducationContent? item;
  final String? initialCategoryId;

  @override
  State<EducationEditorPage> createState() => _EducationEditorPageState();
}

class _EducationEditorPageState extends State<EducationEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _categoryId;
  late String _status;
  bool _saving = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _title = TextEditingController(text: item?.title ?? '');
    _body = TextEditingController(text: item?.body ?? '');
    _categoryId = item?.categoryId ??
        widget.initialCategoryId ??
        widget.categories.first.categoryId;
    _status = item?.publicationStatus ?? 'draft';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save({String? forceStatus}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await EducationContentStore.instance.save(
        contentId: widget.item?.contentId,
        categoryId: _categoryId,
        title: _title.text,
        body: _body.text,
        publicationStatus: forceStatus ?? _status,
        sortOrder: widget.item?.sortOrder,
      );
      if (!mounted) return;
      if (forceStatus == 'published') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مطلب ذخیره و منتشر شد.')),
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ذخیره ناموفق بود: $e')),
      );
    }
  }

  Future<void> _preview() async {
    if (!_formKey.currentState!.validate()) return;
    final content = EducationContent(
      contentId: widget.item?.contentId ?? 'preview',
      categoryId: _categoryId,
      title: _title.text.trim(),
      body: _body.text.trim(),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EducationContentPage(content: content)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'آموزش جدید' : 'ویرایش آموزش'),
          actions: [
            IconButton(
              onPressed: _saving ? null : () => _save(),
              icon: const Icon(Icons.save),
              tooltip: 'ذخیره',
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'دسته آموزشی'),
                items: widget.categories
                    .map((c) => DropdownMenuItem(value: c.categoryId, child: Text(c.title)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'عنوان'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'عنوان الزامی است.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _body,
                minLines: 12,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: 'متن آموزش',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'متن آموزش الزامی است.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'وضعیت'),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Draft / پیش‌نویس')),
                  DropdownMenuItem(value: 'published', child: Text('Published / منتشرشده')),
                  DropdownMenuItem(value: 'archived', child: Text('Archived / آرشیو')),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _saving ? null : _preview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('پیش‌نمایش'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(),
                icon: const Icon(Icons.save),
                label: const Text('ذخیره تغییرات'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : () => _save(forceStatus: 'published'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('ذخیره و تأیید نهایی / Publish'),
              ),
            ],
          ),
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
