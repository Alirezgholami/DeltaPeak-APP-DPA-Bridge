import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../models/user_account.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});
  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  List<UserAccount> _users = const [];
  bool _loading = true;
  String? _error;
  String _sort = 'newest';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await AuthService.instance.listUsers(limit: 200, sort: _sort);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت کاربران'),
          actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'newest', label: Text('جدیدترین'), icon: Icon(Icons.person_add_alt_1)),
                  ButtonSegment(value: 'last_activity', label: Text('آخرین فعالیت'), icon: Icon(Icons.schedule)),
                ],
                selected: {_sort},
                onSelectionChanged: (value) {
                  _sort = value.first;
                  _load();
                },
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
          ]),
        ),
      );
    }
    if (_users.isEmpty) return const Center(child: Text('کاربری برای نمایش وجود ندارد.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final u = _users[i];
          final initial = u.displayName.isEmpty ? '?' : u.displayName.substring(0, 1);
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(initial)),
              title: Text(u.displayName.isEmpty ? u.mobile : u.displayName),
              subtitle: Text(
                '${u.mobile} • ${u.role}\n'
                'عضویت: ${u.createdAtJalali.isEmpty ? '—' : u.createdAtJalali} • آخرین ورود: ${u.lastLoginAtJalali ?? 'ثبت نشده'}\n'
                'آخرین فعالیت: ${u.lastActivityAtJalali ?? 'ثبت نشده'}',
              ),
              isThreeLine: true,
              trailing: Text(u.status),
            ),
          );
        },
      ),
    );
  }
}
