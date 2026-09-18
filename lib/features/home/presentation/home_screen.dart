import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/fx/fx_service.dart';
import '../../../core/i18n/language_settings.dart';
import '../../../core/platform/notification_access.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/theme/theme_settings.dart';
import '../../../core/ui/entity_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../ai/presentation/ai_capture_sheet.dart';
import '../../capture/domain/capture_controller.dart';
import '../../capture/domain/merchant_memory.dart';
import '../../documents/presentation/documents_screen.dart';
import '../../ai/presentation/ai_suggestions_card.dart';
import '../../ai/presentation/planning_screen.dart';
import '../../analytics/domain/analytics_range_provider.dart';
import '../../transactions/domain/category_limits_provider.dart';
import '../../transactions/domain/debts_provider.dart';
import '../../transactions/domain/recurring_transaction.dart';
import '../../transactions/domain/recurring_transactions_provider.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../../transactions/presentation/quick_add_sheet.dart';
import '../domain/home_layout.dart';
import 'home_modules.dart';
import '../../../../design_system/components/ds_card.dart';
import '../../../../design_system/components/ds_empty_state.dart';
import '../../../../design_system/components/ds_list_tile.dart';
import '../../../../design_system/components/ds_section_card.dart';
import '../../../../design_system/components/ds_section_title.dart';
import '../../../../design_system/components/ds_stat_card.dart';
import '../../../../design_system/tokens/ds_motion.dart';
import 'widgets/expense_pie_chart.dart';
import 'widgets/spending_line_chart.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;
  String _accountFilter = 'Todas';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Seed the merchant→category memory from existing categorized movements
      // once, so captures auto-file from day one (cheap, runs on all platforms).
      ref.read(merchantMemoryProvider).maybeSeed();
      // On launch, drain AutoCapture: this syncs native flags and materializes
      // movements the user confirmed/dismissed from the notification while away.
      // Deterministic only (maxAiItems: 0) so launch stays fast.
      if (NotificationAccess.isSupported) {
        ref.read(captureSettingsProvider); // triggers native flag sync
        ref.read(captureInboxProvider.notifier).drainAndProcess(maxAiItems: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(transactionsProvider);
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
    final upcomingPayments = ref.watch(upcomingPaymentsProvider);
    final debtPendingTotal = ref.watch(debtPendingTotalProvider);

    final accounts = {
      'Todas',
      ...entries.map((e) => e.account),
    }.toList();

    final visibleEntries = _accountFilter == 'Todas'
        ? entries
        : entries.where((e) => e.account == _accountFilter).toList();

    final income = visibleEntries
        .where((e) => e.countsAsFlow && e.type == EntryType.income)
        .fold<double>(0, (sum, e) => sum + e.amountMxn);
    final expense = visibleEntries
        .where((e) => e.countsAsFlow && e.type == EntryType.expense)
        .fold<double>(0, (sum, e) => sum + e.amountMxn);
    final balance = income - expense;

    final pages = [
      _DashboardTab(
        entries: visibleEntries,
        upcomingPayments: upcomingPayments,
        balance: money.format(balance),
        income: money.format(income),
        expense: money.format(expense),
        debtPendingTotal: debtPendingTotal,
        money: money,
        accountFilter: _accountFilter,
        accounts: accounts,
        onAccountChanged: (v) => setState(() => _accountFilter = v),
      ),
      _AnalyticsTab(entries: visibleEntries, ref: ref),
      const PlanningScreen(embedded: true),
      const DocumentsScreen(embedded: true),
      const _SettingsTab(),
    ];

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_index) {
          0 => l10n.appTitle,
          1 => l10n.navAnalytics,
          2 => 'Planning',
          3 => 'Documentos',
          _ => l10n.navSettings,
        }),
        actions: [
          if (_index == 0)
            IconButton(
              tooltip: 'Personalizar inicio',
              onPressed: () => context.pushNamed('home-customize'),
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
          IconButton(
            tooltip: 'Captura con IA',
            onPressed: () => showAiCaptureSheet(context, ref),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          IconButton(
            tooltip: 'Recordatorios',
            onPressed: () => context.pushNamed('reminders'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: DsMotion.normal,
        switchInCurve: DsMotion.emphasized,
        switchOutCurve: DsMotion.standard,
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: pages[_index],
        ),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: _quickAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Quick add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: l10n.navHome),
          NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights_rounded), label: l10n.navAnalytics),
          const NavigationDestination(icon: Icon(Icons.auto_graph_outlined), selectedIcon: Icon(Icons.auto_graph_rounded), label: 'Planning'),
          const NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: 'Docs'),
          NavigationDestination(icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune_rounded), label: l10n.navSettings),
        ],
      ),
    );
  }

  Future<void> _quickAdd() async {
    final saved = await showQuickAddSheet(context, ref, accountFilter: _accountFilter);
    if (!mounted || saved == null) return;
    if (_accountFilter != 'Todas' && _accountFilter != saved.account) {
      setState(() => _accountFilter = saved.account);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Movimiento guardado')),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.entries,
    required this.upcomingPayments,
    required this.balance,
    required this.income,
    required this.expense,
    required this.debtPendingTotal,
    required this.money,
    required this.accountFilter,
    required this.accounts,
    required this.onAccountChanged,
  });

  final List<FinanceEntry> entries;
  final List<UpcomingPayment> upcomingPayments;
  final String balance;
  final String income;
  final String expense;
  final double debtPendingTotal;
  final NumberFormat money;
  final String accountFilter;
  final List<String> accounts;
  final ValueChanged<String> onAccountChanged;

  @override
  Widget build(BuildContext context) {
    // Each customizable module maps to its widgets (incl. trailing spacing).
    final sections = <HomeModule, List<Widget>>{
      HomeModule.balance: [
        _BalanceHero(balance: balance, income: income, expense: expense),
        const SizedBox(height: 12),
      ],
      HomeModule.debts: [
        DsListTile(
          icon: Icons.handshake_outlined,
          title: 'Deudas y préstamos',
          subtitle: debtPendingTotal >= 0
              ? 'Neto por cobrar: ${money.format(debtPendingTotal)}'
              : 'Neto por pagar: ${money.format(debtPendingTotal.abs())}',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed('debts'),
        ),
        const SizedBox(height: 10),
      ],
      HomeModule.accounts: [
        DsListTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Cuentas y patrimonio',
          subtitle: 'Saldos por cuenta, transferencias y patrimonio neto',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed('accounts'),
        ),
        const SizedBox(height: 12),
      ],
      HomeModule.hub: const [HomeQuickActions(), SizedBox(height: 18)],
      HomeModule.aiSuggestions: const [AiSuggestionsCard(embedded: true), SizedBox(height: 16)],
      HomeModule.budgetsSummary: const [HomeBudgetsModule(), SizedBox(height: 16)],
      HomeModule.goalsSummary: const [HomeGoalsModule(), SizedBox(height: 16)],
      HomeModule.accountsList: const [HomeAccountsModule(), SizedBox(height: 16)],
      HomeModule.pie: [
        const Row(children: [DsSectionTitle(title: 'Gastos por categoría', icon: Icons.pie_chart_outline_rounded)]),
        const SizedBox(height: 8),
        ExpensePieChart(entries: entries),
        const SizedBox(height: 16),
      ],
      HomeModule.line: [
        const Row(children: [DsSectionTitle(title: 'Tendencia semanal', icon: Icons.show_chart_rounded)]),
        const SizedBox(height: 8),
        SpendingLineChart(entries: entries),
        const SizedBox(height: 16),
      ],
      HomeModule.upcoming: _upcomingSection(context),
      HomeModule.recent: _recentSection(context),
    };

    return Consumer(
      builder: (context, ref, _) {
        final layout = ref.watch(homeLayoutProvider);
        final children = <Widget>[
          Text(_greeting(), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          HomeAccountCards(selected: accountFilter, onSelect: onAccountChanged),
          const SizedBox(height: 18),
        ];
        for (final m in layout.order) {
          if (!layout.isVisible(m)) continue;
          children.addAll(sections[m] ?? const []);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
          children: children,
        );
      },
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  List<Widget> _upcomingSection(BuildContext context) {
    return [
      Row(
        children: [
          const DsSectionTitle(title: 'Próximos pagos', icon: Icons.schedule_rounded),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.pushNamed('recurring'),
            icon: const Icon(Icons.edit_calendar_rounded),
            label: const Text('Gestionar'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (upcomingPayments.isEmpty)
        const DsEmptyState(
          icon: Icons.schedule_rounded,
          title: 'Sin pagos próximos',
          message: 'No hay pagos programados en los próximos 30 días.',
        )
      else
        ...upcomingPayments.map<Widget>((p) {
            final isExpense = p.type == EntryType.expense;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${p.category} · ${DateFormat.yMMMd('es_MX').format(p.dueDate)} · ${p.frequency == RecurringFrequency.weekly ? 'Semanal' : 'Mensual'}${_dueTag(p.dueDate)}',
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isExpense ? '-' : '+'}${money.format(p.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isExpense ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Consumer(
                      builder: (context, ref, _) {
                        return PopupMenuButton<String>(
                          tooltip: 'Acciones',
                          onSelected: (value) {
                            if (value == 'done') {
                              ref.read(transactionsProvider.notifier).add(
                                    FinanceEntry(
                                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                                      title: p.title,
                                      amount: p.amount,
                                      category: p.category,
                                      date: DateTime.now(),
                                      type: p.type,
                                    ),
                                  );
                              ref.read(recurringTransactionsProvider.notifier).completeOccurrence(p.recurringId);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Registrado y movido al siguiente ${p.frequency == RecurringFrequency.weekly ? 'ciclo semanal' : 'ciclo mensual'}')),
                              );
                            } else if (value == 'snooze') {
                              ref.read(recurringTransactionsProvider.notifier).snooze(p.recurringId, days: 1);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pago pospuesto 1 día')),
                              );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'done', child: Text('Registrar ahora')),
                            PopupMenuItem(value: 'snooze', child: Text('Posponer 1 día')),
                          ],
                          child: const Icon(Icons.more_horiz_rounded),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
      ];
  }

  List<Widget> _recentSection(BuildContext context) {
    return [
      Row(
        children: [
          const DsSectionTitle(title: 'Movimientos recientes', icon: Icons.receipt_long_rounded),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.pushNamed('transactions'),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Ver todos'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (entries.isEmpty)
        const DsEmptyState(
          icon: Icons.wallet_outlined,
          title: 'Aún no tienes movimientos',
          message: 'Empieza agregando tu primer gasto o ingreso.',
        )
      else
        ...entries.take(10).map((e) => _EntryTile(entry: e, money: money)),
    ];
  }

  String _dueTag(DateTime dueDate) {
    final today = DateTime.now();
    final a = DateTime(today.year, today.month, today.day);
    final b = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = b.difference(a).inDays;

    if (days <= 0) return ' · Hoy';
    if (days == 1) return ' · Mañana';
    if (days <= 3) return ' · En $days días';
    return '';
  }
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab({required this.entries, required this.ref});

  final List<FinanceEntry> entries;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider);
    final selectedOffset = ref.watch(analyticsPeriodOffsetProvider);
    final hasSelectedPeriod = selectedOffset >= 0;
    final activeOffset = hasSelectedPeriod ? selectedOffset : 0;
    final (start, end) = analyticsRangeToDatesWithOffset(range, activeOffset);

    // All aggregates below only count realized, non-transfer movements.
    final flowEntries = entries.where((e) => e.countsAsFlow).toList();
    final filtered = flowEntries.where((e) => !e.date.isBefore(start) && !e.date.isAfter(end)).toList();

    ({double income, double expense, double net}) periodTotals(AnalyticsRangePreset preset) {
      final (ps, pe) = analyticsRangeToDatesWithOffset(preset, 0);
      final period = flowEntries.where((e) => !e.date.isBefore(ps) && !e.date.isAfter(pe));
      final income = period
          .where((e) => e.type == EntryType.income)
          .fold<double>(0, (s, e) => s + e.amountMxn);
      final expense = period
          .where((e) => e.type == EntryType.expense)
          .fold<double>(0, (s, e) => s + e.amountMxn);
      return (income: income, expense: expense, net: income - expense);
    }

    String periodFeedLabel(int offset) {
      final (s, e) = analyticsRangeToDatesWithOffset(range, offset);
      if (range == AnalyticsRangePreset.monthToDate) {
        return DateFormat('MMMM yyyy', 'es_MX').format(s);
      }
      if (range == AnalyticsRangePreset.yearToDate) {
        return DateFormat('yyyy', 'es_MX').format(s);
      }
      return '${DateFormat('d MMM', 'es_MX').format(s)} - ${DateFormat('d MMM', 'es_MX').format(e)}';
    }

    final maxPeriods = switch (range) {
      AnalyticsRangePreset.last7 => 26,
      AnalyticsRangePreset.last30 => 18,
      AnalyticsRangePreset.monthToDate => 24,
      AnalyticsRangePreset.yearToDate => 8,
    };

    ({int offset, String label, double income, double expense})? periodFeedItem(int offset) {
      final (ps, pe) = analyticsRangeToDatesWithOffset(range, offset);
      final period = flowEntries.where((e) => !e.date.isBefore(ps) && !e.date.isAfter(pe));
      final income = period
          .where((e) => e.type == EntryType.income)
          .fold<double>(0, (s, e) => s + e.amountMxn);
      final expense = period
          .where((e) => e.type == EntryType.expense)
          .fold<double>(0, (s, e) => s + e.amountMxn);
      if (income <= 0 && expense <= 0) return null;
      return (offset: offset, label: periodFeedLabel(offset), income: income, expense: expense);
    }

    final availablePeriods = [
      for (var i = 0; i < maxPeriods; i++)
        if (periodFeedItem(i) case final item?) item,
    ];

    final totalExpense = filtered
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (s, e) => s + e.amountMxn);
    final totalIncome = filtered
        .where((e) => e.type == EntryType.income)
        .fold<double>(0, (s, e) => s + e.amountMxn);

    final days = end.difference(start).inDays + 1;
    final prevEnd = start.subtract(const Duration(seconds: 1));
    final prevStart = DateTime(prevEnd.year, prevEnd.month, prevEnd.day).subtract(Duration(days: days - 1));

    final previous = flowEntries.where((e) => !e.date.isBefore(prevStart) && !e.date.isAfter(prevEnd)).toList();

    final prevExpense = previous
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (s, e) => s + e.amountMxn);
    final prevIncome = previous
        .where((e) => e.type == EntryType.income)
        .fold<double>(0, (s, e) => s + e.amountMxn);

    final net = totalIncome - totalExpense;
    final prevNet = prevIncome - prevExpense;

    final budgets = ref.watch(monthlyCategoryBudgetsProvider);

    double periodLimitFromMonthly(double monthlyLimit) {
      return switch (range) {
        AnalyticsRangePreset.last7 => monthlyLimit * (7 / 30),
        AnalyticsRangePreset.last30 => monthlyLimit,
        AnalyticsRangePreset.monthToDate => monthlyLimit,
        AnalyticsRangePreset.yearToDate => monthlyLimit * 12,
      };
    }

    final spent = <String, double>{};
    for (final e in filtered) {
      if (e.type != EntryType.expense) continue;
      spent[e.category] = (spent[e.category] ?? 0) + e.amountMxn;
    }
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

    final isYearView = range == AnalyticsRangePreset.yearToDate;

    final bucketLabels = <String>[];
    final incomeSeries = <double>[];
    final expenseSeries = <double>[];
    final netSeries = <double>[];

    if (isYearView) {
      for (var m = 1; m <= 12; m++) {
        final inMonth = filtered
            .where((e) => e.type == EntryType.income)
            .where((e) => e.date.year == start.year && e.date.month == m)
            .fold<double>(0, (sum, e) => sum + e.amountMxn);
        final outMonth = filtered
            .where((e) => e.type == EntryType.expense)
            .where((e) => e.date.year == start.year && e.date.month == m)
            .fold<double>(0, (sum, e) => sum + e.amountMxn);

        final monthLabel = DateFormat.MMM('es_MX').format(DateTime(start.year, m, 1));
        bucketLabels.add(monthLabel[0].toUpperCase() + monthLabel.substring(1));
        incomeSeries.add(inMonth);
        expenseSeries.add(outMonth);
        netSeries.add(inMonth - outMonth);
      }
    } else {
      final dayCount = end.difference(start).inDays + 1;
      final dayBuckets = List.generate(dayCount, (i) => DateTime(start.year, start.month, start.day + i));

      for (final day in dayBuckets) {
        final inDay = filtered
            .where((e) => e.type == EntryType.income)
            .where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day)
            .fold<double>(0, (sum, e) => sum + e.amountMxn);
        final outDay = filtered
            .where((e) => e.type == EntryType.expense)
            .where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day)
            .fold<double>(0, (sum, e) => sum + e.amountMxn);

        bucketLabels.add('${day.day}');
        incomeSeries.add(inDay);
        expenseSeries.add(outDay);
        netSeries.add(inDay - outDay);
      }
    }

    final currentByCategory = <String, double>{};
    final prevByCategory = <String, double>{};

    for (final e in filtered.where((e) => e.type == EntryType.expense)) {
      currentByCategory[e.category] = (currentByCategory[e.category] ?? 0) + e.amountMxn;
    }
    for (final e in previous.where((e) => e.type == EntryType.expense)) {
      prevByCategory[e.category] = (prevByCategory[e.category] ?? 0) + e.amountMxn;
    }

    final trendCategories = currentByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topCategory = trendCategories.isEmpty ? null : trendCategories.first;
    final topCategoryPct = (topCategory == null || totalExpense <= 0)
        ? 0.0
        : (topCategory.value / totalExpense) * 100;

    final budgetRiskCount = budgets.entries.where((b) {
      final used = spent[b.key] ?? 0;
      final limit = periodLimitFromMonthly(b.value);
      if (limit <= 0) return false;
      return (used / limit) >= 0.8;
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!hasSelectedPeriod) ...[
          Text('Periodos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in AnalyticsRangePreset.values) ...[
                  _PeriodOverviewCard(
                    label: switch (preset) {
                      AnalyticsRangePreset.last7 => '7 días',
                      AnalyticsRangePreset.last30 => '30 días',
                      AnalyticsRangePreset.monthToDate => 'MTD',
                      AnalyticsRangePreset.yearToDate => 'YTD',
                    },
                    totals: periodTotals(preset),
                    selected: preset == range,
                    onTap: () {
                      ref.read(analyticsRangeProvider.notifier).state = preset;
                      ref.read(analyticsPeriodOffsetProvider.notifier).state = -1;
                    },
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!hasSelectedPeriod) ...[
          Text('Historial de periodos', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (availablePeriods.isEmpty)
            const DsEmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: 'Sin periodos con movimientos',
              message: 'Cuando existan transacciones, aparecerán aquí.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: availablePeriods.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = availablePeriods[i];
                return _PeriodFeedTile(
                  label: item.label,
                  income: money.format(item.income),
                  expense: money.format(item.expense),
                  selected: false,
                  onTap: () => ref.read(analyticsPeriodOffsetProvider.notifier).state = item.offset,
                );
              },
            ),
          const SizedBox(height: 8),
        ],
        if (hasSelectedPeriod) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Detalle: ${periodFeedLabel(activeOffset)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => ref.read(analyticsPeriodOffsetProvider.notifier).state = -1,
                child: const Text('Cambiar periodo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (hasSelectedPeriod) ...[
          DsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Neto del periodo', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                money.format(net),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                _deltaText(current: net, previous: prevNet, higherIsBetter: true),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _isDeltaPositive(current: net, previous: prevNet, higherIsBetter: true)
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _MetricTile(label: 'Ingreso', value: money.format(totalIncome))),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricTile(label: 'Gasto', value: money.format(totalExpense))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        DsSectionCard(
          title: 'Insights rápidos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InsightRow(
                icon: Icons.category_outlined,
                text: topCategory == null
                    ? 'Aún no hay categoría dominante en este periodo.'
                    : '${topCategory.key} concentra ${topCategoryPct.toStringAsFixed(0)}% del gasto del periodo.',
              ),
              const SizedBox(height: 8),
              _InsightRow(
                icon: Icons.warning_amber_rounded,
                text: budgetRiskCount == 0
                    ? 'Sin categorías en riesgo de límite (80%+).'
                    : '$budgetRiskCount categorías están cerca o sobre su límite temporal.',
              ),
              const SizedBox(height: 8),
              _InsightRow(
                icon: Icons.insights_outlined,
                text: 'Neto ${_deltaText(current: net, previous: prevNet, higherIsBetter: true)} vs periodo anterior.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DsSectionCard(
          title: 'Cashflow del periodo',
          child: _CashflowTrendChart(
            labels: bucketLabels,
            incomeSeries: incomeSeries,
            expenseSeries: expenseSeries,
            netSeries: netSeries,
          ),
        ),
        const SizedBox(height: 12),
        DsSectionCard(
          title: 'Tendencia por categoría',
          child: trendCategories.isEmpty
              ? const Text('Sin suficientes datos para tendencia de categorías.')
              : Column(
                  children: trendCategories.take(6).map((item) {
                    final prev = prevByCategory[item.key] ?? 0;
                    final change = prev == 0 ? null : ((item.value - prev) / prev) * 100;
                    final up = (change ?? 0) > 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(money.format(item.value)),
                          const SizedBox(width: 8),
                          Text(
                            change == null ? 'nuevo' : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: change == null
                                  ? Theme.of(context).colorScheme.secondary
                                  : (up ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        DsSectionCard(
          title: 'Presupuestos por categoría',
          action: TextButton(
            onPressed: () => context.pushNamed('category-limits'),
            child: const Text('Configurar límites'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...budgets.entries.map((b) {
                final used = spent[b.key] ?? 0;
                final periodLimit = periodLimitFromMonthly(b.value);
                final ratio = periodLimit <= 0 ? 0.0 : (used / periodLimit).clamp(0.0, 1.0);
                final over = used > periodLimit;
                final near = !over && ratio >= 0.8;
                final progressColor = over
                    ? Theme.of(context).colorScheme.error
                    : near
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.primary;

                final status = over
                    ? 'Excedido'
                    : near
                        ? 'Cerca del límite'
                        : 'En rango';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(b.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${money.format(used)} / ${money.format(periodLimit)}'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(status, style: TextStyle(fontSize: 12, color: progressColor, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: ratio, color: progressColor),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        ],
      ],
    );
  }

  String _deltaText({required double current, required double previous, required bool higherIsBetter}) {
    if (previous == 0) {
      if (current == 0) return 'Sin cambio';
      return 'Nuevo periodo';
    }

    final change = ((current - previous) / previous) * 100;
    final sign = change >= 0 ? '+' : '';
    final tag = higherIsBetter
        ? (change >= 0 ? 'mejor' : 'baja')
        : (change <= 0 ? 'mejor' : 'sube');
    return '$sign${change.toStringAsFixed(1)}% · $tag';
  }

  bool _isDeltaPositive({required double current, required double previous, required bool higherIsBetter}) {
    if (previous == 0) return current > 0;
    return higherIsBetter ? current >= previous : current <= previous;
  }
}

class _PeriodFeedTile extends StatelessWidget {
  const _PeriodFeedTile({
    required this.label,
    required this.income,
    required this.expense,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String income;
  final String expense;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
          border: Border.all(color: selected ? scheme.secondary : scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Text('↑ $income', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('↓ $expense', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.error, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _PeriodOverviewCard extends StatelessWidget {
  const _PeriodOverviewCard({
    required this.label,
    required this.totals,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ({double income, double expense, double net}) totals;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.compactCurrency(locale: 'es_MX', symbol: r'$');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Neto ${money.format(totals.net)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('↑ ${money.format(totals.income)}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary)),
            Text('↓ ${money.format(totals.expense)}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.error)),
          ],
        ),
      ),
    );
  }
}

class _CashflowTrendChart extends StatelessWidget {
  const _CashflowTrendChart({
    required this.labels,
    required this.incomeSeries,
    required this.expenseSeries,
    required this.netSeries,
  });

  final List<String> labels;
  final List<double> incomeSeries;
  final List<double> expenseSeries;
  final List<double> netSeries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxAbs = [
      ...incomeSeries,
      ...expenseSeries,
      ...netSeries.map((e) => e.abs()),
    ].fold<double>(0, (m, v) => v.abs() > m ? v.abs() : m);

    if (maxAbs == 0) {
      return const SizedBox(height: 120, child: Center(child: Text('Sin movimientos en el rango')));
    }

    final upper = maxAbs * 1.2;
    final interval = upper <= 0 ? 1.0 : upper / 2;

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          minY: -upper,
          maxY: upper,
          groupsSpace: 10,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: value == 0 ? scheme.outline : scheme.outlineVariant.withValues(alpha: 0.45),
              strokeWidth: value == 0 ? 1.3 : 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: interval,
                getTitlesWidget: (value, meta) => Text(
                  value == 0 ? '0' : NumberFormat.compact(locale: 'es_MX').format(value),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();

                  final step = labels.length > 24 ? 5 : (labels.length > 12 ? 3 : 1);
                  final isLast = i == labels.length - 1;
                  final shouldShow = i % step == 0 || isLast;
                  if (!shouldShow) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i]),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(labels.length, (i) {
            final income = incomeSeries[i];
            final expense = expenseSeries[i];
            return BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: income,
                  width: 8,
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                BarChartRodData(
                  toY: -expense,
                  width: 8,
                  color: scheme.error,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const DsListTile(icon: Icons.payments_outlined, title: 'Moneda', subtitle: 'MXN'),
        Builder(builder: (context) {
          final fx = ref.watch(fxProvider);
          final subtitle = fx.loading
              ? 'Actualizando…'
              : (fx.updatedAt == null
                  ? 'Usando tasas estáticas · toca para actualizar'
                  : 'Actualizado ${DateFormat('d MMM HH:mm', 'es_MX').format(fx.updatedAt!)}');
          return DsListTile(
            icon: Icons.currency_exchange_rounded,
            title: 'Tipos de cambio',
            subtitle: subtitle,
            trailing: const Icon(Icons.refresh_rounded),
            onTap: () async {
              final ok = await ref.read(fxProvider.notifier).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Tasas actualizadas' : 'No se pudieron actualizar las tasas')),
                );
              }
            },
          );
        }),
        Builder(builder: (context) {
          final ts = ref.watch(themeSettingsProvider);
          final modeLabel = ts.mode == ThemeMode.light
              ? 'Claro'
              : ts.mode == ThemeMode.dark
                  ? 'Oscuro'
                  : 'Sistema';
          return DsListTile(
            icon: Icons.palette_outlined,
            title: 'Tema y color',
            subtitle: '$modeLabel · ${ts.accent == null ? 'Color dinámico' : 'Acento personalizado'}',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showThemeSheet(context, ref),
          );
        }),
        DsListTile(
          icon: Icons.auto_awesome_rounded,
          title: 'Inteligencia artificial',
          subtitle: 'API key, modelo, captura por IA',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed('ai-settings'),
        ),
        DsListTile(
          icon: Icons.tune_rounded,
          title: 'Captura y layout',
          subtitle: 'Quick Add, Batch Add, modo IA y plantillas',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed('capture-layout'),
        ),
        Builder(builder: (context) {
          final locale = ref.watch(languageProvider);
          final lang = locale == null ? 'system' : locale.languageCode;
          final l10n = AppLocalizations.of(context);
          final label = lang == 'es'
              ? l10n.languageSpanish
              : lang == 'en'
                  ? l10n.languageEnglish
                  : l10n.languageSystem;
          return DsListTile(
            icon: Icons.translate_rounded,
            title: l10n.language,
            subtitle: label,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showLanguageSheet(context, ref),
          );
        }),
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline_rounded),
          title: const Text('Bloqueo con biometría'),
          subtitle: const Text('Pide huella/rostro o PIN al abrir Nexo'),
          value: ref.watch(appLockProvider).enabled,
          onChanged: (v) async {
            final ok = await ref.read(appLockProvider.notifier).setEnabled(v);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se pudo configurar el bloqueo (autenticación fallida).')),
              );
            }
          },
        ),
        DsListTile(
          icon: Icons.import_export_rounded,
          title: 'Datos y respaldos',
          subtitle: 'Exportar CSV, respaldo completo y restaurar',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed('data'),
        ),
        DsListTile(
          icon: Icons.science_outlined,
          title: 'Cargar datos demo',
          subtitle: 'Generar 300 transacciones dummy',
          onTap: () {
            ref.read(transactionsProvider.notifier).generateDummyTransactions(count: 300);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Se agregaron 300 transacciones demo')),
            );
          },
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.income, required this.expense});

  final String balance;
  final String income;
  final String expense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balance actual', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(balance, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: DsStatCard(label: 'Ingresos', value: income, icon: Icons.trending_up_rounded)),
                const SizedBox(width: 10),
                Expanded(child: DsStatCard(label: 'Gastos', value: expense, icon: Icons.trending_down_rounded)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.money});

  final FinanceEntry entry;
  final NumberFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = entry.type == EntryType.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => context.pushNamed('add', extra: entry),
        leading: CircleAvatar(
          backgroundColor: (isExpense ? scheme.errorContainer : scheme.primaryContainer),
          child: Icon(
            isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: isExpense ? scheme.error : scheme.primary,
          ),
        ),
        title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${entry.category} · ${entry.account} · ${DateFormat.yMMMd('es_MX').format(entry.date)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isExpense ? '-' : '+'}${entry.currency == 'MXN' ? money.format(entry.amount) : '${entry.currency} ${entry.amount.toStringAsFixed(2)}'}',
              style: TextStyle(fontWeight: FontWeight.w900, color: isExpense ? scheme.error : scheme.primary),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  context.pushNamed('add', extra: entry);
                } else if (value == 'delete') {
                  ref.read(transactionsProvider.notifier).remove(entry.id);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento eliminado')));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


Future<void> _showThemeSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final ts = ref.watch(themeSettingsProvider);
        final notifier = ref.read(themeSettingsProvider.notifier);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tema y color',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              Text('Modo', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto_rounded)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode_rounded)),
                ],
                selected: {ts.mode},
                onSelectionChanged: (s) => notifier.setMode(s.first),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Color de acento', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => notifier.setAccent(null),
                    child: const Text('Dinámico'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ColorSwatchPicker(
                selected: ts.accent ?? -1,
                onSelect: (c) => notifier.setAccent(c),
              ),
              const SizedBox(height: 8),
              Text(
                ts.accent == null
                    ? 'Usando Material You (color del sistema cuando está disponible).'
                    : 'Acento personalizado activo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showLanguageSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final current = ref.watch(languageProvider);
        final currentKey = current == null ? 'system' : current.languageCode;
        final notifier = ref.read(languageProvider.notifier);
        Widget option(String key, String label) => ListTile(
              title: Text(label),
              trailing: currentKey == key ? const Icon(Icons.check_rounded) : null,
              onTap: () {
                notifier.setLanguage(key);
                Navigator.pop(context);
              },
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.language,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              option('system', l10n.languageSystem),
              option('es', l10n.languageSpanish),
              option('en', l10n.languageEnglish),
            ],
          ),
        );
      },
    ),
  );
}
