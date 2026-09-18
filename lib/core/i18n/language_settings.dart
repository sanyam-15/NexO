import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/local_store.dart';

/// App language preference. `null` locale means "follow the system".
class LanguageController extends StateNotifier<Locale?> {
  LanguageController() : super(const Locale('es')) {
    final v = _meta('language');
    state = _localeFor(v.isEmpty ? 'es' : v);
  }

  String _meta(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  static Locale? _localeFor(String key) {
    switch (key) {
      case 'es':
        return const Locale('es');
      case 'en':
        return const Locale('en');
      default:
        return null; // system
    }
  }

  /// 'system' | 'es' | 'en'
  String get key {
    final l = state;
    return l == null ? 'system' : l.languageCode;
  }

  void setLanguage(String key) {
    _set('language', key);
    state = _localeFor(key);
  }
}

final languageProvider = StateNotifierProvider<LanguageController, Locale?>(
  (ref) => LanguageController(),
);
