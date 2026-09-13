import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_account.dart';

class SessionStore extends ChangeNotifier {
  SessionStore._();
  static final instance = SessionStore._();

  static const _accessKey = 'dpa_access_token';
  static const _refreshKey = 'dpa_refresh_token';
  static const _profileKey = 'dpa_user_profile';
  static const bool _internalOwnerMode = bool.fromEnvironment(
    'DPA_INTERNAL_OWNER_MODE',
    defaultValue: false,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  UserAccount? _user;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  UserAccount? get currentUser => _user;
  bool get isSignedIn => _accessToken != null && _user != null;
  bool get isInternalOwnerMode => _internalOwnerMode;
  bool get canManageReferenceData => (_user?.isAdmin ?? false) || _internalOwnerMode;

  Future<void> load() async {
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    final raw = await _storage.read(key: _profileKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _user = UserAccount.fromJson(json);
      notifyListeners();
    } catch (_) {
      await clear();
    }
  }

  Future<void> save({
    required String accessToken,
    String? refreshToken,
    required UserAccount user,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _user = user;
    await _storage.write(key: _accessKey, value: accessToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      await _storage.delete(key: _refreshKey);
    } else {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
    await _storage.write(key: _profileKey, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> updateUser(UserAccount user) async {
    _user = user;
    await _storage.write(key: _profileKey, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _profileKey);
    notifyListeners();
  }
}
