import 'package:flutter/material.dart';
import '../data/peak_repository.dart';
import '../models/peak.dart';
import 'peak_detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Peak> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final items = await PeakRepository.instance.search(favoritesOnly: true);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _remove(Peak peak) async {
    await PeakRepository.instance.toggleFavorite(peak);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('علاقه‌مندی‌ها')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: const [
                          SizedBox(height: 120),
                          Icon(Icons.favorite_border, size: 56),
                          SizedBox(height: 12),
                          Center(child: Text('هنوز قله‌ای به علاقه‌مندی‌ها اضافه نشده است.')),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final peak = _items[index];
                          return Card(
                            child: ListTile(
                              leading: IconButton(
                                tooltip: 'حذف از علاقه‌مندی‌ها',
                                onPressed: () => _remove(peak),
                                icon: const Icon(Icons.favorite, color: Colors.redAccent),
                              ),
                              title: Text(peak.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                peak.province,
                                if (peak.county != null && peak.county!.trim().isNotEmpty) peak.county!,
                                if (peak.elevation != null) '${peak.elevation}m',
                              ].join(' • ')),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () async {
                                await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(builder: (_) => PeakDetailPage(peak: peak)),
                                );
                                await _load();
                              },
                            ),
                          );
                        },
                      ),
              ),
      );
}
