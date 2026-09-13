import 'package:flutter/material.dart';
import '../data/peak_repository.dart';
import '../models/peak.dart';

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});
  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  List<Peak> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await PeakRepository.instance.deletedPeaks();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _restore(Peak peak) async {
    await PeakRepository.instance.restorePeak(peak.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سطل بازیابی')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _items.isEmpty
                    ? ListView(children: const [SizedBox(height: 120), Center(child: Text('رکورد حذف‌شده‌ای وجود ندارد.'))])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(p.name),
                              subtitle: Text('${p.province} • ${p.id}'),
                              trailing: FilledButton.tonal(onPressed: () => _restore(p), child: const Text('بازیابی')),
                            ),
                          );
                        },
                      ),
              ),
      );
}
