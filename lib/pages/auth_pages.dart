import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../data/peak_repository.dart';
import '../utils/phone.dart';

String? _mobileValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'شماره موبایل الزامی است.';
  return PhoneUtils.isValidIranMobile(value) ? null : 'شماره موبایل معتبر نیست.';
}

String? _passwordValidator(String? value) {
  if (value == null || value.length < 8) return 'رمز عبور باید حداقل ۸ کاراکتر باشد.';
  return null;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _key = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await AuthService.instance.login(mobile: _mobile.text, password: _password.text);
      await PeakRepository.instance.cacheUserProfile(user);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ورود / Sign in')),
        body: Form(
          key: _key,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('نام کاربری همان شماره موبایل است.', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                validator: _mobileValidator,
                decoration: const InputDecoration(labelText: 'شماره موبایل / نام کاربری', hintText: '09123456789'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                validator: _passwordValidator,
                decoration: const InputDecoration(labelText: 'رمز عبور'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.login),
                label: Text(_busy ? 'در حال ورود…' : 'ورود'),
              ),
            ],
          ),
        ),
      );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  int _resendIn = 0;
  int _expiresIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _mobile.dispose();
    _password.dispose();
    _repeat.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startTimer(int resend, int expires) {
    _timer?.cancel();
    setState(() {
      _resendIn = resend;
      _expiresIn = expires;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_resendIn > 0) _resendIn--;
        if (_expiresIn > 0) _expiresIn--;
      });
      if (_resendIn <= 0 && _expiresIn <= 0) timer.cancel();
    });
  }

  Future<void> _requestCode({bool resend = false}) async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final challenge = await AuthService.instance.requestRegistrationCode(_mobile.text, resend: resend);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
      _startTimer(challenge.resendAfterSeconds, challenge.expiresInSeconds);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirm() async {
    if (!_key.currentState!.validate()) return;
    if (_code.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کد تأیید را وارد کنید.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final user = await AuthService.instance.confirmRegistration(
        displayName: _name.text,
        mobile: _mobile.text,
        code: _code.text,
        password: _password.text,
      );
      await PeakRepository.instance.cacheUserProfile(user);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ثبت‌نام امن')),
        body: Form(
          key: _key,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('شماره موبایل شما نام کاربری DPA است و قبل از ساخت حساب با کد پیامکی تأیید می‌شود.',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_codeSent,
                validator: (v) => v == null || v.trim().isEmpty ? 'نام نمایشی الزامی است.' : null,
                decoration: const InputDecoration(labelText: 'نام نمایشی'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                enabled: !_codeSent,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                validator: _mobileValidator,
                decoration: const InputDecoration(labelText: 'شماره موبایل / نام کاربری', hintText: '09123456789'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                enabled: !_codeSent,
                obscureText: true,
                validator: _passwordValidator,
                decoration: const InputDecoration(labelText: 'رمز عبور'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeat,
                enabled: !_codeSent,
                obscureText: true,
                validator: (v) => v != _password.text ? 'تکرار رمز عبور یکسان نیست.' : null,
                decoration: const InputDecoration(labelText: 'تکرار رمز عبور'),
              ),
              const SizedBox(height: 18),
              if (!_codeSent)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _requestCode(),
                  icon: const Icon(Icons.sms_outlined),
                  label: Text(_busy ? 'در حال ارسال…' : 'ارسال کد تأیید'),
                ),
              if (_codeSent) ...[
                Text('کد تأیید تا $_expiresIn ثانیه معتبر است.'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'کد تأیید پیامکی'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || _expiresIn <= 0 ? null : _confirm,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(_expiresIn <= 0 ? 'کد منقضی شده' : (_busy ? 'در حال ساخت حساب…' : 'تأیید و ایجاد حساب')),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy || _resendIn > 0 ? null : () => _requestCode(resend: true),
                      child: Text(_resendIn > 0 ? 'ارسال مجدد ($_resendIn)' : 'ارسال مجدد کد'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _timer?.cancel();
                            setState(() {
                              _codeSent = false;
                              _code.clear();
                              _expiresIn = 0;
                              _resendIn = 0;
                            });
                          },
                    child: const Text('ویرایش اطلاعات'),
                  ),
                ]),
              ],
            ],
          ),
        ),
      );
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _key = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _newPassword = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _newPassword.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.changePassword(currentPassword: _old.text, newPassword: _newPassword.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز عبور تغییر کرد.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تغییر رمز عبور')),
        body: Form(
          key: _key,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(controller: _old, obscureText: true, validator: _passwordValidator, decoration: const InputDecoration(labelText: 'رمز فعلی')),
              const SizedBox(height: 12),
              TextFormField(controller: _newPassword, obscureText: true, validator: _passwordValidator, decoration: const InputDecoration(labelText: 'رمز جدید')),
              const SizedBox(height: 12),
              TextFormField(controller: _repeat, obscureText: true, validator: (v) => v != _newPassword.text ? 'تکرار رمز یکسان نیست.' : null, decoration: const InputDecoration(labelText: 'تکرار رمز جدید')),
              const SizedBox(height: 18),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('تغییر رمز')),
            ],
          ),
        ),
      );
}

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key});
  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _key = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  int _resendIn = 0;
  int _expiresIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _mobile.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startTimer(int resend, int expires) {
    _timer?.cancel();
    setState(() {
      _resendIn = resend;
      _expiresIn = expires;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_resendIn > 0) _resendIn--;
        if (_expiresIn > 0) _expiresIn--;
      });
      if (_resendIn <= 0 && _expiresIn <= 0) timer.cancel();
    });
  }

  Future<void> _request({bool resend = false}) async {
    if (!PhoneUtils.isValidIranMobile(_mobile.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شماره موبایل معتبر نیست.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final challenge = await AuthService.instance.requestPasswordReset(_mobile.text, resend: resend);
      if (!mounted) return;
      _codeSent = true;
      _busy = false;
      _startTimer(challenge.resendAfterSeconds, challenge.expiresInSeconds);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reset() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.resetPassword(mobile: _mobile.text, code: _code.text, newPassword: _password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز جدید ثبت شد. اکنون وارد شوید.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('بازیابی رمز عبور')),
        body: Form(
          key: _key,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _mobile,
                enabled: !_codeSent,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.phone,
                validator: _mobileValidator,
                decoration: const InputDecoration(labelText: 'شماره موبایل'),
              ),
              const SizedBox(height: 12),
              if (!_codeSent)
                FilledButton.icon(onPressed: _busy ? null : () => _request(), icon: const Icon(Icons.sms_outlined), label: const Text('ارسال کد بازیابی')),
              if (_codeSent) ...[
                Text('کد تا $_expiresIn ثانیه معتبر است.'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  validator: (v) => v == null || v.trim().length < 4 ? 'کد را وارد کنید.' : null,
                  decoration: const InputDecoration(labelText: 'کد یک‌بارمصرف'),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _password, obscureText: true, validator: _passwordValidator, decoration: const InputDecoration(labelText: 'رمز عبور جدید')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: FilledButton(onPressed: _busy || _expiresIn <= 0 ? null : _reset, child: Text(_expiresIn <= 0 ? 'کد منقضی شده' : 'ثبت رمز جدید'))),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _busy || _resendIn > 0 ? null : () => _request(resend: true), child: Text(_resendIn > 0 ? 'ارسال مجدد ($_resendIn)' : 'ارسال مجدد کد')),
                ]),
              ],
            ],
          ),
        ),
      );
}
