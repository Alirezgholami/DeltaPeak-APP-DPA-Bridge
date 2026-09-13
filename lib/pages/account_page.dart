import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../auth/session_store.dart';
import '../models/user_account.dart';
import 'auth_pages.dart';
import 'user_management_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  UserAccount? get _user => SessionStore.instance.currentUser;
  bool _backendChecking = false;
  bool? _backendReachable;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    if (!AuthService.instance.isConfigured) {
      if (mounted) setState(() => _backendReachable = false);
      return;
    }
    setState(() => _backendChecking = true);
    final ok = await AuthService.instance.pingBackend();
    if (!mounted) return;
    setState(() {
      _backendReachable = ok;
      _backendChecking = false;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    try {
      await AuthService.instance.logout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خروج سرور کامل نشد، نشست محلی پاک شد: $e')));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('حساب کاربری')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _backendCard(),
          const SizedBox(height: 10),
          if (user == null) _guestCard() else _userCard(user),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('امنیت: رمز عبور، OTP و Token در SQLite/Backup ذخیره نمی‌شوند. Token نشست فقط در Secure Storage سیستم‌عامل نگهداری می‌شود.'),
            ),
          ),
        ],
      ),
    );
  }


  Widget _backendCard() {
    final configured = AuthService.instance.isConfigured;
    final ok = _backendReachable == true;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: configured && ok ? scheme.secondaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                !configured
                    ? 'Backend روی این Build تنظیم نشده است.'
                    : _backendChecking
                        ? 'در حال بررسی سرور…'
                        : ok
                            ? 'سرور و دیتابیس DPA در دسترس هستند.'
                            : 'سرور یا دیتابیس DPA در دسترس نیست.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          if (configured) ...[
            const SizedBox(height: 8),
            SelectableText(AuthService.instance.baseUrl, textDirection: TextDirection.ltr),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _backendChecking ? null : _checkBackend,
            icon: const Icon(Icons.sync),
            label: const Text('بررسی اتصال Backend'),
          ),
        ]),
      ),
    );
  }

  Widget _guestCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('ورود به DPA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            const Text('نام کاربری شما همان شماره موبایل است.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: () => _open(const LoginPage()), icon: const Icon(Icons.login), label: const Text('ورود / Login')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _open(const RegisterPage()), icon: const Icon(Icons.person_add_alt_1), label: const Text('ثبت‌نام / Sign up')),
            TextButton(onPressed: () => _open(const PasswordResetPage()), child: const Text('رمز عبور را فراموش کرده‌ام')),
          ]),
        ),
      );

  Widget _userCard(UserAccount user) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const Divider(),
            _row('نام کاربری', user.mobile),
            _row('نقش', user.role),
            _row('وضعیت', user.status),
            _row('عضویت', user.createdAtJalali),
            _row('آخرین ورود', user.lastLoginAtJalali ?? 'ثبت نشده'),
            _row('آخرین فعالیت', user.lastActivityAtJalali ?? 'ثبت نشده'),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => _open(const ChangePasswordPage()), icon: const Icon(Icons.password), label: const Text('تغییر رمز عبور')),
            if (user.isAdmin) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(onPressed: () => _open(const UserManagementPage()), icon: const Icon(Icons.manage_accounts_outlined), label: const Text('فهرست کاربران و آخرین ورودها')),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('خروج / Sign out')),
          ]),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 105, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: SelectableText(value)),
        ]),
      );
}
