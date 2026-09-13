import 'dart:async';
import 'package:flutter/widgets.dart';
import 'auth_service.dart';
import 'session_store.dart';

class SessionCoordinator with WidgetsBindingObserver {
  SessionCoordinator._();
  static final instance = SessionCoordinator._();

  static const _heartbeatInterval = Duration(minutes: 5);
  DateTime? _lastHeartbeat;
  Timer? _heartbeatTimer;
  bool _started = false;
  bool _foreground = true;
  bool _busy = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _scheduleHeartbeat());
    _scheduleProfileSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _scheduleProfileSync();
    }
  }

  void _scheduleProfileSync() {
    Future<void>.microtask(_syncProfile);
  }

  void _scheduleHeartbeat() {
    if (!_foreground) return;
    Future<void>.microtask(_heartbeat);
  }

  bool get _canContactBackend =>
      AuthService.instance.isConfigured && SessionStore.instance.isSignedIn;

  Future<void> _syncProfile() async {
    if (_busy || !_canContactBackend) return;
    _busy = true;
    try {
      // /me both revalidates the session/profile and counts as current activity.
      await AuthService.instance.syncCurrentUser();
      _lastHeartbeat = DateTime.now();
    } on AuthException catch (e) {
      await _handleAuthFailure(e);
    } catch (_) {
      // DPA remains offline-first; background session sync is best-effort.
    } finally {
      _busy = false;
    }
  }

  Future<void> _heartbeat() async {
    if (_busy || !_canContactBackend) return;
    final now = DateTime.now();
    if (_lastHeartbeat != null && now.difference(_lastHeartbeat!) < _heartbeatInterval) return;
    _busy = true;
    try {
      await AuthService.instance.touchActivity();
      _lastHeartbeat = now;
    } on AuthException catch (e) {
      await _handleAuthFailure(e);
    } catch (_) {
      // A temporary outage should not break offline use or wipe a cached session.
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleAuthFailure(AuthException e) async {
    if (e.code == 'not_authenticated' || e.code == 'refresh_token_missing') {
      await SessionStore.instance.clear();
    }
  }
}
