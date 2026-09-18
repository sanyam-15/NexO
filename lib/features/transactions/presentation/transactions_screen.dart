import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/ds_empty_state.dart';
import '../../categories/domain/categories_provider.dart';
import '../domain/currency.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';

enum _TypeFilter { all, expense, income, transfer }

enum _RangeFilter { all, thisMonth, last30 }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  _TypeFilter _type = _TypeFilter.all;
  _RangeFilter _range = _RangeFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesRange(DateTime d) {
    final now = DateTime.now();
    switch (_range) {
      case _RangeFilter.all:
        return true;
      case _RangeFilter.thisMonth:
        return d.year == now.year && d.month == now.month;
      case _RangeFilter.last30:
        return d.isAfter(now.subtract(const Duration(days: 30)));
    }
  }

  bool _matchesType(FinanceEntry e) {
    switch (_type) {
      case _TypeFilter.all:
        return true;
      case _TypeFilter.transfer:
        return e.kind == EntryKind.transfer;
      case _TypeFilter.expense:
        return e.kind != EntryKind.transfer && e.type == EntryType.expense;
      case _TypeFilter.income:
        return e.kind != EntryKind.transfer && e.type == EntryType.income;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(transactionsProvider);
    final resolveCat = ref.watch(categoryByKeyProvider);
    final q = _search.text.trim().toLowerCase();

    final filtered = all.where((e) {
      if (!_matchesType(e)) return false;
      if (!_matchesRange(e.date)) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          e.account.toLowerCase().contains(q) ||
          (e.note?.toLowerCase().contains(q) ?? false);
    }).toList();

    final total = filtered
        .where((e) => e.kind != EntryKind.transfer && e.paid)
        .fold<double>(0, (s, e) => s + (e.type == EntryType.expense ? -1 : 1) * toMxnWithRate(e.amount, e.currency, e.exchangeRate));

    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed('add'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Movimiento'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Buscar concepto, categoría, cuenta o nota',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _search.clear()),
                      ),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _chip('Todos', _type == _TypeFilter.all, () => setState(() => _type = _TypeFilter.all)),
                _chip('Gastos', _type == _TypeFilter.expense, () => setState(() => _type = _TypeFilter.expense)),
                _chip('Ingresos', _type == _TypeFilter.income, () => setState(() => _type = _TypeFilter.income)),
                _chip('Transfers', _type == _TypeFilter.transfer, () => setState(() => _type = _TypeFilter.transfer)),
                const SizedBox(width: 8),
                const VerticalDivider(width: 1),
                const SizedBox(width: 8),
                _chip('Todo', _range == _RangeFilter.all, () => setState(() => _range = _RangeFilter.all)),
                _chip('Este mes', _range == _RangeFilter.thisMonth, () => setState(() => _range = _RangeFilter.thisMonth)),
                _chip('30 días', _range == _RangeFilter.last30, () => setState(() => _range = _RangeFilter.last30)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${filtered.length} movimientos', style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                Text(
                  'Neto: ${formatMoney(total)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: total >= 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: DsEmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Sin resultados',
                        message: 'Ajusta los filtros o registra un nuevo movimiento.',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      final cat = resolveCat(e.categoryId, e.category);
                      return _TxTile(entry: e, emoji: e.kind == EntryKind.transfer ? '🔁' : (cat?.emoji ?? '🏷️'));
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}

class _TxTile extends ConsumerWidget {
  const _TxTile({required this.entry, required this.emoji});
  final FinanceEntry entry;
  final String emoji;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isTransfer = entry.kind == EntryKind.transfer;
    final isExpense = entry.type == EntryType.expense;
    final df = DateFormat('d MMM', 'es_MX');
    final color = isTransfer
        ? theme.colorScheme.onSurfaceVariant
        : (isExpense ? theme.colorScheme.error : theme.colorScheme.primary);
    final sign = isTransfer ? '' : (isExpense ? '−' : '+');

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Eliminar movimiento'),
                content: Text('¿Eliminar "${entry.title}"?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => ref.read(transactionsProvider.notifier).remove(entry.id),
      child: ListTile(
        onTap: () => context.pushNamed('add', extra: entry),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Text(emoji),
        ),
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${df.format(entry.date)} · ${entry.account}${entry.paid ? '' : ' · pendiente'}'),
        trailing: Text(
          '$sign${formatMoney(entry.amount, currency: entry.currency)}',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }
}
