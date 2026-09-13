import 'package:flutter/material.dart';
import '../data/peak_repository.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();
  static final instance = AppThemeController._();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final saved = await PeakRepository.instance.getSetting('theme_mode');
    _mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    await PeakRepository.instance.setSetting('theme_mode', mode.name);
    notifyListeners();
  }
}
