import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import 'capture_layout.dart';
import 'transaction.dart';

/// Persists the capture layout config + saved templates as JSON blobs in
/// `app_meta` (mirrors the ai_config pattern). Backward-compatible: an absent
/// blob yields [CaptureLayoutConfig.defaults], which reproduces today's UI.
class CaptureLayoutNotifier extends StateNotifier<CaptureLayoutConfig> {
  CaptureLayoutNotifier() : super(CaptureLayoutConfig.defaults) {
    _load();
  }

  static const _key = 'capture_layout';
  static const _templatesKey = 'capture_templates';

  String _meta(String key, String fallback) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  void _load() {
    final raw = _meta(_key, '');
    if (raw.trim().isEmpty) return;
    try {
      state = CaptureLayoutConfig.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {/* corrupt → keep defaults */}
  }

  void _save(CaptureLayoutConfig cfg) {
    _set(_key, jsonEncode(cfg.toJson()));
    state = cfg;
  }

  void setMode(QuickAddMode mode) => _save(state.copyWith(quickAddMode: mode));

  void setDocumentEngine(DocumentEngine engine) => _save(state.copyWith(documentEngine: engine));

  void setDocumentOcr(DocumentOcr ocr) => _save(state.copyWith(documentOcr: ocr));

  /// Updates the remote-OCR config. Pass only the fields to change; a null
  /// argument keeps the current value (to blank a field, pass '').
  void setOcrEndpoint({String? endpoint, String? apiKey, String? model}) {
    _save(state.copyWith(ocrEndpoint: endpoint, ocrApiKey: apiKey, ocrModel: model));
  }

  void setDefaults({
    EntryType? type,
    String? categoryName,
    bool clearCategory = false,
    String? accountName,
    bool clearAccount = false,
    String? currency,
  }) {
    _save(state.copyWith(
      defaultType: type,
      defaultCategoryName: categoryName,
      clearDefaultCategory: clearCategory,
      defaultAccountName: accountName,
      clearDefaultAccount: clearAccount,
      defaultCurrency: currency,
    ));
  }

  void toggleField(CaptureField field, bool visible, {bool batch = false}) {
    final list = batch ? state.batchAddFields : state.quickAddFields;
    final updated = [
      for (final c in list) c.field == field ? c.copyWith(visible: visible) : c,
    ];
    _save(batch ? state.copyWith(batchAddFields: updated) : state.copyWith(quickAddFields: updated));
  }

  void reorderField(int oldIndex, int newIndex, {bool batch = false}) {
    final list = [...(batch ? state.batchAddFields : state.quickAddFields)];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _save(batch ? state.copyWith(batchAddFields: list) : state.copyWith(quickAddFields: list));
  }

  void resetDefaults() => _save(CaptureLayoutConfig.defaults);

  // ---- templates ------------------------------------------------------------

  List<CaptureTemplate> templates() {
    final raw = _meta(_templatesKey, '');
    if (raw.trim().isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List);
      return [for (final j in list) if (j is Map) CaptureTemplate.fromJson(j.cast<String, dynamic>())];
    } catch (_) {
      return const [];
    }
  }

  void _saveTemplates(List<CaptureTemplate> list) {
    _set(_templatesKey, jsonEncode([for (final t in list) t.toJson()]));
  }

  void saveTemplate(String name) {
    final list = [...templates(), CaptureTemplate(id: newId('tpl'), name: name, config: state)];
    _saveTemplates(list);
    state = state.copyWith(); // notify listeners so the template list rebuilds
  }

  void deleteTemplate(String id) {
    _saveTemplates([for (final t in templates()) if (t.id != id) t]);
    state = state.copyWith(); // notify listeners so the template list rebuilds
  }

  void applyTemplate(String id) {
    for (final t in templates()) {
      if (t.id == id) {
        _save(t.config);
        return;
      }
    }
  }
}

final captureLayoutProvider =
    StateNotifierProvider<CaptureLayoutNotifier, CaptureLayoutConfig>(
  (ref) => CaptureLayoutNotifier(),
);
