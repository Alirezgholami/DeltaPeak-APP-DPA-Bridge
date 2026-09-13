import 'package:flutter/material.dart';
import 'auth/session_coordinator.dart';
import 'auth/session_store.dart';
import 'data/peak_identity_deduper.dart';
import 'data/peak_repository.dart';
import 'pages/home_page.dart';
import 'theme/app_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PeakRepository.instance.initialize();
  await PeakIdentityDeduper.run(PeakRepository.instance.databasePath);
  await PeakRepository.instance.ensureDatabaseReady();
  await SessionStore.instance.load();
  await AppThemeController.instance.load();
  SessionCoordinator.instance.start();
  runApp(const DeltaPeakApp());
}

class DeltaPeakApp extends StatelessWidget {
  const DeltaPeakApp({super.key});

  ThemeData _theme(Brightness brightness) {
    const seed = Color(0xFF176B52);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppThemeController.instance,
        builder: (context, _) => MaterialApp(
          title: 'Delta Peak',
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa', 'IR'),
          themeMode: AppThemeController.instance.mode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: true,
              child: child!,
            ),
          ),
          home: const HomePage(),
        ),
      );
}
