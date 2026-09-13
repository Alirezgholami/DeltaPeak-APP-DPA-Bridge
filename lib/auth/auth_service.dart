import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_account.dart';
import '../utils/phone.dart';
import 'session_store.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class OtpChallenge {
  const OtpChallenge({this.expiresInSeconds = 120, this.resendAfterSeconds = 60});
  final int expiresInSeconds;
  final int resendAfterSeconds;
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'DPA_API_BASE_URL',
    defaultValue: '',
  );

  final http.Client _client = http.Client();
  static const Duration _requestTimeout = Duration(seconds: 20);
  Future<UserAccount>? _refreshing;

  String get baseUrl => _configuredBaseUrl.replaceAll(RegExp(r'/+$'), '');
  bool get isConfigured => baseUrl.isNotEmpty;
  bool get isHttpsConfigured => Uri.tryParse(baseUrl)?.scheme.toLowerCase() == 'https';
  UserAccount? get currentUser => SessionStore.instance.currentUser;

  Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw const AuthException(
        'Backend احراز هویت هنوز تنظیم نشده است. DPA_API_BASE_URL باید هنگام Build مشخص شود.',
        code: 'backend_not_configured',
      );
    }
    if (kReleaseMode && !isHttpsConfigured) {
      throw const AuthException(
        'نسخه Release فقط به Backend امن HTTPS متصل می‌شود.',
        code: 'insecure_backend_url',
      );
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool auth = false}) {
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (auth) {
      final token = SessionStore.instance.accessToken;
      if (token == null || token.isEmpty) {
        throw const AuthException('نشست کاربری معتبر نیست.', code: 'not_authenticated');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        throw AuthException('پاسخ نامعتبر از سرور (${response.statusCode}).', code: 'invalid_response');
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final message = (body['message'] ?? body['error'] ?? 'خطای سرور (${response.statusCode})').toString();
    throw AuthException(message, code: body['code']?.toString());
  }

  Map<String, dynamic> _payload(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map<String, dynamic> ? data : body;
  }

  Future<http.Response> _network(Future<http.Response> request) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw const AuthException('پاسخی از سرور دریافت نشد. اتصال اینترنت را بررسی کنید.', code: 'network_timeout');
    } on http.ClientException {
      throw const AuthException('ارتباط با سرور برقرار نشد. اتصال اینترنت را بررسی کنید.', code: 'network_error');
    }
  }

  Future<UserAccount> refreshSession() async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final refreshToken = SessionStore.instance.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthException('نشست کاربری منقضی شده است. دوباره وارد شوید.', code: 'refresh_token_missing');
    }
    final future = _doRefresh(refreshToken);
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<UserAccount> _doRefresh(String refreshToken) async {
    try {
      final response = await _network(_client.post(
        _uri('/v1/auth/refresh'),
        headers: _headers(),
        body: jsonEncode({'refresh_token': refreshToken}),
      ));
      return _acceptSession(await _decode(response));
    } on AuthException catch (e) {
      const terminalCodes = {'invalid_refresh_token', 'account_inactive'};
      if (terminalCodes.contains(e.code)) {
        await SessionStore.instance.clear();
      }
      rethrow;
    }
  }

  Future<http.Response> _authorized(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var response = await _network(send(_headers(auth: true)));
    if (response.statusCode != 401 || SessionStore.instance.refreshToken == null) return response;
    await refreshSession();
    response = await _network(send(_headers(auth: true)));
    return response;
  }

  Future<UserAccount> _acceptSession(Map<String, dynamic> body) async {
    final data = _payload(body);
    final userRaw = data['user'];
    if (userRaw is! Map) throw const AuthException('اطلاعات کاربر در پاسخ سرور وجود ندارد.');
    final accessToken = (data['access_token'] ?? data['accessToken'])?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw const AuthException('Access Token در پاسخ سرور وجود ندارد.');
    }
    final user = UserAccount.fromJson(Map<String, dynamic>.from(userRaw));
    await SessionStore.instance.save(
      accessToken: accessToken,
      refreshToken: (data['refresh_token'] ?? data['refreshToken'])?.toString(),
      user: user,
    );
    return user;
  }

  Future<UserAccount> login({required String mobile, required String password}) async {
    final normalized = PhoneUtils.normalizeIranMobile(mobile);
    if (!PhoneUtils.isValidIranMobile(normalized)) {
      throw const AuthException('شماره موبایل معتبر نیست. نمونه: 09123456789');
    }
    final response = await _network(_client.post(
      _uri('/v1/auth/login'),
      headers: _headers(),
      body: jsonEncode({'mobile': normalized, 'username': normalized, 'password': password}),
    ));
    return _acceptSession(await _decode(response));
  }

  Future<OtpChallenge> requestRegistrationCode(String mobile, {bool resend = false}) async {
    final normalized = PhoneUtils.normalizeIranMobile(mobile);
    if (!PhoneUtils.isValidIranMobile(normalized)) {
      throw const AuthException('شماره موبایل معتبر نیست. نمونه: 09123456789');
    }
    final response = await _network(_client.post(
      _uri('/v1/auth/register/request'),
      headers: _headers(),
      body: jsonEncode({'mobile': normalized, 'resend': resend}),
    ));
    final data = _payload(await _decode(response));
    return OtpChallenge(
      expiresInSeconds: int.tryParse('${data['expires_in_seconds'] ?? 120}') ?? 120,
      resendAfterSeconds: int.tryParse('${data['resend_after_seconds'] ?? 60}') ?? 60,
    );
  }

  Future<UserAccount> confirmRegistration({
    required String displayName,
    required String mobile,
    required String code,
    required String password,
  }) async {
    final normalized = PhoneUtils.normalizeIranMobile(mobile);
    if (!PhoneUtils.isValidIranMobile(normalized)) {
      throw const AuthException('شماره موبایل معتبر نیست. نمونه: 09123456789');
    }
    final response = await _network(_client.post(
      _uri('/v1/auth/register/confirm'),
      headers: _headers(),
      body: jsonEncode({
        'display_name': displayName.trim(),
        'mobile': normalized,
        'code': code.trim(),
        'password': password,
      }),
    ));
    return _acceptSession(await _decode(response));
  }

  Future<void> logout() async {
    try {
      if (isConfigured && SessionStore.instance.accessToken != null) {
        final response = await _authorized((headers) => _client.post(_uri('/v1/auth/logout'), headers: headers));
        await _decode(response);
      }
    } finally {
      await SessionStore.instance.clear();
    }
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final response = await _authorized((headers) => _client.post(
      _uri('/v1/auth/change-password'),
      headers: headers,
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
    ));
    final body = await _decode(response);
    final data = _payload(body);
    if (data['access_token'] != null || data['accessToken'] != null) {
      await _acceptSession(body);
    }
  }

  Future<OtpChallenge> requestPasswordReset(String mobile, {bool resend = false}) async {
    final normalized = PhoneUtils.normalizeIranMobile(mobile);
    if (!PhoneUtils.isValidIranMobile(normalized)) {
      throw const AuthException('شماره موبایل معتبر نیست.');
    }
    final response = await _network(_client.post(
      _uri('/v1/auth/password-reset/request'),
      headers: _headers(),
      body: jsonEncode({'mobile': normalized, 'resend': resend}),
    ));
    final data = _payload(await _decode(response));
    return OtpChallenge(
      expiresInSeconds: int.tryParse('${data['expires_in_seconds'] ?? 120}') ?? 120,
      resendAfterSeconds: int.tryParse('${data['resend_after_seconds'] ?? 60}') ?? 60,
    );
  }

  Future<void> resetPassword({
    required String mobile,
    required String code,
    required String newPassword,
  }) async {
    final normalized = PhoneUtils.normalizeIranMobile(mobile);
    final response = await _network(_client.post(
      _uri('/v1/auth/password-reset/confirm'),
      headers: _headers(),
      body: jsonEncode({'mobile': normalized, 'code': code.trim(), 'new_password': newPassword}),
    ));
    await _decode(response);
  }

  Future<UserAccount> syncCurrentUser() async {
    final response = await _authorized((headers) => _client.get(
      _uri('/v1/auth/me'),
      headers: headers,
    ));
    final body = _payload(await _decode(response));
    final raw = body['user'] ?? body;
    if (raw is! Map) {
      throw const AuthException('اطلاعات حساب کاربری از سرور دریافت نشد.', code: 'invalid_user_response');
    }
    final user = UserAccount.fromJson(Map<String, dynamic>.from(raw));
    await SessionStore.instance.updateUser(user);
    return user;
  }

  Future<UserAccount> touchActivity() async {
    final response = await _authorized((headers) => _client.post(
      _uri('/v1/auth/activity'),
      headers: headers,
    ));
    final body = _payload(await _decode(response));
    final raw = body['user'] ?? body;
    if (raw is! Map) {
      throw const AuthException('ثبت فعالیت کاربر تأیید نشد.', code: 'invalid_activity_response');
    }
    final user = UserAccount.fromJson(Map<String, dynamic>.from(raw));
    await SessionStore.instance.updateUser(user);
    return user;
  }

  Future<bool> pingBackend() async {
    if (!isConfigured) return false;
    try {
      final response = await _network(_client.get(_uri('/ready'), headers: _headers()));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<UserAccount>> listUsers({int limit = 100, String sort = 'newest'}) async {
    final role = currentUser?.role;
    if (role != 'owner' && role != 'admin') {
      throw const AuthException('این بخش فقط برای Owner و Admin مجاز است.', code: 'forbidden');
    }
    final response = await _authorized((headers) => _client.get(
      _uri('/v1/admin/users', {'limit': '$limit', 'sort': sort}),
      headers: headers,
    ));
    final body = _payload(await _decode(response));
    final raw = body['users'] ?? body['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => UserAccount.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<UserAccount> updateUserRole({required String userId, required String role}) async {
    if (currentUser?.role != 'owner') {
      throw const AuthException('فقط Owner می‌تواند دسترسی Admin را تفویض یا لغو کند.', code: 'owner_required');
    }
    if (role != 'user' && role != 'admin') {
      throw const AuthException('نقش انتخاب‌شده معتبر نیست.', code: 'invalid_role');
    }
    final response = await _authorized((headers) => _client.patch(
      _uri('/v1/admin/users/$userId/role'),
      headers: headers,
      body: jsonEncode({'role': role}),
    ));
    final body = _payload(await _decode(response));
    final raw = body['user'] ?? body;
    if (raw is! Map) {
      throw const AuthException('پاسخ تفویض دسترسی معتبر نیست.', code: 'invalid_user_response');
    }
    return UserAccount.fromJson(Map<String, dynamic>.from(raw));
  }
}
