import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/local_store.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/fx/fx_service.dart';
import 'core/notifications/notification_service.dart';
import 'features/data/domain/auto_backup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _bootstrap();
    runApp(const ProviderScope(child: NexoApp()));
  } catch (e, st) {
    // Last-resort guard: show what failed instead of a dead black screen.
    debugPrint('Nexo bootstrap failed: $e\n$st');
    runApp(BootErrorApp(error: e.toString()));
  }
}

/// Strict order: date formatting -> LocalStore -> Firebase. Only LocalStore is
/// load-bearing, and it falls back to an in-memory store internally instead of
/// throwing; every other step degrades independently so a bad plugin or
/// missing resource can't leave the app stuck before the first frame.
Future<void> _bootstrap() async {
  try {
    await initializeDateFormatting('es_MX');
  } catch (e) {
    debugPrint('initializeDateFormatting failed: $e');
  }
  await LocalStore.init();
  try {
    loadCachedFxRates();
  } catch (e) {
    debugPrint('loadCachedFxRates failed: $e');
  }
  try {
    await AutoBackup.maybeRunOnLaunch();
  } catch (e) {
    debugPrint('AutoBackup.maybeRunOnLaunch failed: $e');
  }
  try {
    await FirebaseBootstrap.initialize();
  } catch (e) {
    debugPrint('FirebaseBootstrap.initialize failed: $e');
  }
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('NotificationService.init failed: $e');
  }
}

/// Minimal emergency screen shown when bootstrap itself throws. Deliberately
/// avoids the design system and theming: at this point nothing else is
/// guaranteed to be initialized.
class BootErrorApp extends StatelessWidget {
  const BootErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Nexo no pudo iniciar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reinicia la app. Si el problema sigue, reporta este error:\n\n$error',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
