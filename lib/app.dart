import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/local_store.dart';
import 'core/i18n/language_settings.dart';
import 'core/router/app_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_settings.dart';
import 'design_system/tokens/ds_spacing.dart';
import 'l10n/app_localizations.dart';

class NexoApp extends ConsumerWidget {
  const NexoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    final locale = ref.watch(languageProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // A chosen accent overrides dynamic color; otherwise use Material You.
        ColorScheme? lightScheme = lightDynamic;
        ColorScheme? darkScheme = darkDynamic;
        if (themeSettings.accent != null) {
          final seed = Color(themeSettings.accent!);
          lightScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
          darkScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
        }
        return MaterialApp.router(
          title: 'Nexo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dynamicScheme: lightScheme),
          darkTheme: AppTheme.dark(dynamicScheme: darkScheme),
          themeMode: themeSettings.mode,
          routerConfig: router,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => AppLockGate(
            child: _DegradedStoreNotice(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

/// Banner shown when [LocalStore] booted on the in-memory fallback: the
/// session works but nothing persists, and the on-disk data was not touched.
/// Without it, an empty app would read as silent data loss.
class _DegradedStoreNotice extends StatelessWidget {
  const _DegradedStoreNotice({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (LocalStore.startupError == null) return child;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.errorContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpacing.md,
                vertical: DsSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer, size: 20),
                  const SizedBox(width: DsSpacing.xs),
                  Expanded(
                    child: Text(
                      'No se pudo abrir la base de datos local: esta sesión es '
                      'temporal y no se guardará. Tus datos en el dispositivo '
                      'no se modificaron.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
