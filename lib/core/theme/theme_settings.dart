import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/local_store.dart';

class ThemeSettings {
  const ThemeSettings({this.mode = ThemeMode.system, this.accent});

  final ThemeMode mode;

  /// ARGB accent seed. Null = use dynamic color (Material You) when available.
  final int? accent;

  ThemeSettings copyWith({ThemeMode? mode, int? accent, bool clearAccent = false}) =>
      ThemeSettings(mode: mode ?? this.mode, accent: clearAccent ? null : (accent ?? this.accent));
}

class ThemeSettingsController extends StateNotifier<ThemeSettings> {
  ThemeSettingsController() : super(const ThemeSettings()) {
    final modeStr = _meta('theme_mode');
    final accentStr = _meta('theme_accent');
    state = ThemeSettings(
      mode: _modeFromKey(modeStr),
      accent: accentStr.isEmpty ? null : int.tryParse(accentStr),
    );
  }

  String _meta(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  static ThemeMode _modeFromKey(String k) {
    switch (k) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void setMode(ThemeMode mode) {
    _set('theme_mode', mode.name);
    state = state.copyWith(mode: mode);
  }

  /// Pass null to revert to dynamic color.
  void setAccent(int? accent) {
    _set('theme_accent', accent?.toString() ?? '');
    state = state.copyWith(accent: accent, clearAccent: accent == null);
  }
}

final themeSettingsProvider = StateNotifierProvider<ThemeSettingsController, ThemeSettings>(
  (ref) => ThemeSettingsController(),
);
