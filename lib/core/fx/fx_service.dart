import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/transactions/domain/currency.dart';
import '../db/local_store.dart';

class FxState {
  const FxState({this.updatedAt, this.loading = false, this.rates = const {}});
  final DateTime? updatedAt;
  final bool loading;
  final Map<String, double> rates; // MXN per unit

  FxState copyWith({DateTime? updatedAt, bool? loading, Map<String, double>? rates}) =>
      FxState(updatedAt: updatedAt ?? this.updatedAt, loading: loading ?? this.loading, rates: rates ?? this.rates);
}

/// Fetches and caches live MXN exchange rates so multi-currency totals reflect
/// reality instead of frozen constants. Free, key-less endpoint; falls back to
/// the static table on any failure.
class FxController extends StateNotifier<FxState> {
  FxController() : super(const FxState()) {
    _loadCached();
  }

  static const _endpoint = 'https://open.er-api.com/v6/latest/MXN';

  String _meta(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  void _loadCached() {
    final json = _meta('fx_rates_json');
    if (json.isEmpty) return;
    try {
      final map = (jsonDecode(json) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
      liveMxnPerCurrency
        ..clear()
        ..addAll(map);
      final ts = _meta('fx_updated_at');
      state = state.copyWith(rates: map, updatedAt: DateTime.tryParse(ts));
    } catch (_) {/* ignore corrupt cache */}
  }

  Future<bool> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final res = await http.get(Uri.parse(_endpoint)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rates = (body['rates'] as Map?) ?? const {};
      final out = <String, double>{};
      for (final code in supportedCurrencies) {
        if (code == 'MXN') continue;
        final perMxn = (rates[code] as num?)?.toDouble(); // units of `code` per 1 MXN
        if (perMxn != null && perMxn > 0) out[code] = 1 / perMxn; // -> MXN per 1 unit
      }
      if (out.isEmpty) throw Exception('Sin tasas en la respuesta');

      liveMxnPerCurrency
        ..clear()
        ..addAll(out);
      final now = DateTime.now();
      _set('fx_rates_json', jsonEncode(out));
      _set('fx_updated_at', now.toIso8601String());
      state = state.copyWith(rates: out, updatedAt: now, loading: false);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('FX refresh failed: $e');
      state = state.copyWith(loading: false);
      return false;
    }
  }
}

final fxProvider = StateNotifierProvider<FxController, FxState>((ref) => FxController());

/// Loads cached FX rates into [liveMxnPerCurrency] at startup so conversions are
/// fresh before any provider is read. Safe no-op if no cache exists.
void loadCachedFxRates() {
  try {
    final rows = LocalStore.db.select("SELECT value FROM app_meta WHERE key = 'fx_rates_json'");
    if (rows.isEmpty) return;
    final map = (jsonDecode(rows.first['value'] as String) as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    liveMxnPerCurrency
      ..clear()
      ..addAll(map);
  } catch (_) {/* ignore */}
}
