import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';

/// Customizable dashboard modules, in their default order.
enum HomeModule {
  balance,
  debts,
  accounts,
  hub,
  aiSuggestions,
  budgetsSummary,
  goalsSummary,
  accountsList,
  pie,
  line,
  upcoming,
  recent,
}

extension HomeModuleX on HomeModule {
  String get label {
    switch (this) {
      case HomeModule.balance:
        return 'Balance';
      case HomeModule.debts:
        return 'Deudas y préstamos';
      case HomeModule.accounts:
        return 'Cuentas y patrimonio';
      case HomeModule.hub:
        return 'Accesos rápidos';
      case HomeModule.aiSuggestions:
        return 'Sugerencias IA';
      case HomeModule.budgetsSummary:
        return 'Resumen de presupuestos';
      case HomeModule.goalsSummary:
        return 'Resumen de metas';
      case HomeModule.accountsList:
        return 'Lista de cuentas';
      case HomeModule.pie:
        return 'Gastos por categoría';
      case HomeModule.line:
        return 'Tendencia semanal';
      case HomeModule.upcoming:
        return 'Próximos pagos';
      case HomeModule.recent:
        return 'Movimientos recientes';
    }
  }

  IconData get icon {
    switch (this) {
      case HomeModule.balance:
        return Icons.account_balance_wallet_rounded;
      case HomeModule.debts:
        return Icons.handshake_outlined;
      case HomeModule.accounts:
        return Icons.savings_outlined;
      case HomeModule.hub:
        return Icons.grid_view_rounded;
      case HomeModule.aiSuggestions:
        return Icons.lightbulb_rounded;
      case HomeModule.budgetsSummary:
        return Icons.account_balance_rounded;
      case HomeModule.goalsSummary:
        return Icons.savings_rounded;
      case HomeModule.accountsList:
        return Icons.account_balance_wallet_rounded;
      case HomeModule.pie:
        return Icons.pie_chart_outline_rounded;
      case HomeModule.line:
        return Icons.show_chart_rounded;
      case HomeModule.upcoming:
        return Icons.schedule_rounded;
      case HomeModule.recent:
        return Icons.receipt_long_rounded;
    }
  }
}

class HomeLayout {
  const HomeLayout({required this.order, required this.hidden});

  final List<HomeModule> order;
  final Set<HomeModule> hidden;

  bool isVisible(HomeModule m) => !hidden.contains(m);

  /// Hidden on a fresh install to keep the default home clean: the standalone
  /// debts/accounts tiles and the duplicate accounts list are reachable from the
  /// quick-action chips, so they start off and can be enabled in customization.
  static const defaultHidden = <HomeModule>{
    HomeModule.debts,
    HomeModule.accounts,
    HomeModule.accountsList,
  };

  HomeLayout copyWith({List<HomeModule>? order, Set<HomeModule>? hidden}) =>
      HomeLayout(order: order ?? this.order, hidden: hidden ?? this.hidden);
}

class HomeLayoutController extends StateNotifier<HomeLayout> {
  HomeLayoutController()
      : super(HomeLayout(order: List.of(HomeModule.values), hidden: const {})) {
    _load();
  }

  String _meta(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  void _load() {
    final orderStr = _meta('home_order');
    final firstRun = orderStr.isEmpty;

    final order = _parse(orderStr);
    // Any modules not present in the saved order (e.g. new ones) are appended.
    for (final m in HomeModule.values) {
      if (!order.contains(m)) order.add(m);
    }
    // First run gets the curated clean default; afterwards respect saved state.
    final hidden = firstRun ? Set.of(HomeLayout.defaultHidden) : _parse(_meta('home_hidden')).toSet();
    state = HomeLayout(order: order, hidden: hidden);
  }

  List<HomeModule> _parse(String csv) {
    if (csv.isEmpty) return [];
    final byName = {for (final m in HomeModule.values) m.name: m};
    return csv.split(',').map((s) => byName[s.trim()]).whereType<HomeModule>().toList();
  }

  void _persist() {
    _set('home_order', state.order.map((m) => m.name).join(','));
    _set('home_hidden', state.hidden.map((m) => m.name).join(','));
  }

  void reorder(int oldIndex, int newIndex) {
    final order = List.of(state.order);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    state = state.copyWith(order: order);
    _persist();
  }

  void setVisible(HomeModule m, bool visible) {
    final hidden = Set.of(state.hidden);
    if (visible) {
      hidden.remove(m);
    } else {
      hidden.add(m);
    }
    state = state.copyWith(hidden: hidden);
    _persist();
  }

  void reset() {
    state = HomeLayout(order: List.of(HomeModule.values), hidden: const {});
    _persist();
  }
}

final homeLayoutProvider = StateNotifierProvider<HomeLayoutController, HomeLayout>(
  (ref) => HomeLayoutController(),
);
