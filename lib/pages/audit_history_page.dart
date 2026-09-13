import 'package:flutter/material.dart';
import '../data/peak_repository.dart';
import '../models/audit_entry.dart';

class AuditHistoryPage extends StatefulWidget {
  const AuditHistoryPage({super.key, required this.peakId, required this.peakName});
  final String peakId;
  final String peakName;

  @override
  State<AuditHistoryPage> createState() => _AuditHistoryPageState();
}

class _AuditHistoryPageState extends State<AuditHistoryPage> {
  List<AuditEntry> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await PeakRepository.instance.auditForPeak(widget.peakId);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('تاریخچه ${widget.peakName}')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                    ? const Center(child: Text('تغییری ثبت نشده است.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final a = _items[i];
                          final field = a.fieldName == null ? '' : '\nفیلد: ${a.fieldName}';
                          final values = a.oldValue == null && a.newValue == null ? '' : '\n${a.oldValue ?? '—'} ← ${a.newValue ?? '—'}';
                          return Card(
                            child: ListTile(
                              title: Text('${a.action} • ${a.entityType}'),
                              subtitle: Text('${a.changedAtJalali}\n${a.actor}$field$values'),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
      );
}
