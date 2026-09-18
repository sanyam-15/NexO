import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/util/ids.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_input.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../../design_system/components/ds_select.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../ai/domain/ai_providers.dart';
import '../../categories/domain/categories_provider.dart';
import '../../categories/domain/category.dart';
import '../../labels/domain/labels_provider.dart';
import '../domain/currency.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';

enum _Mode { expense, income, transfer }

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.initialEntry});

  final FinanceEntry? initialEntry;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  _Mode _mode = _Mode.expense;
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  String _currency = 'MXN';
  late DateTime _date;
  bool _initialized = false;
  bool _suggesting = false;
  final Set<String> _labelIds = {};

  @override
  void initState() {
    super.initState();
    _date = widget.initialEntry?.date ?? DateTime.now();
    final initial = widget.initialEntry;
    if (initial != null) {
      _title.text = initial.title;
      _amount.text = initial.amount.toStringAsFixed(initial.amount.truncateToDouble() == initial.amount ? 0 : 2);
      _currency = initial.currency;
      _categoryId = initial.categoryId;
      _accountId = initial.accountId;
      _toAccountId = initial.transferAccountId;
      _note.text = initial.note ?? '';
      _mode = initial.kind == EntryKind.transfer
          ? _Mode.transfer
          : (initial.type == EntryType.income ? _Mode.income : _Mode.expense);
      _labelIds.addAll(ref.read(labelsProvider.notifier).labelIdsFor(initial.id));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _ensureDefaults(List<Category> cats, List<Account> accounts) {
    if (_initialized) return;
    _initialized = true;
    final initial = widget.initialEntry;
    if (initial == null) {
      _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
      _categoryId ??= cats.isNotEmpty ? cats.first.id : null;
    } else {
      // Resolve legacy string refs from older rows by name.
      _accountId ??= _matchByName(accounts.map((a) => (a.id, a.name)), initial.account);
      _categoryId ??= _matchByName(cats.map((c) => (c.id, c.name)), initial.category);
    }
  }

  String? _matchByName(Iterable<(String, String)> items, String name) {
    for (final it in items) {
      if (it.$2.toLowerCase() == name.toLowerCase()) return it.$1;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activeAccountsProvider);
    final allCats = ref.watch(activeCategoriesProvider).where((c) => !c.isSubcategory).toList();
    _ensureDefaults(allCats, accounts);

    final cats = allCats.where((c) {
      if (_mode == _Mode.income) return c.type != CategoryType.expense;
      return c.type != CategoryType.income;
    }).toList();
    if (cats.isNotEmpty && !cats.any((c) => c.id == _categoryId)) _categoryId = cats.first.id;

    final df = DateFormat('EEE d MMM yyyy', 'es_MX');
    final isTransfer = _mode == _Mode.transfer;

    return DsScreenScaffold(
      title: widget.initialEntry == null ? 'Nuevo movimiento' : 'Editar movimiento',
      children: [
        const DsFeatureHeader(
          title: 'Registra un movimiento',
          subtitle: 'Gasto, ingreso o transferencia entre cuentas.',
          icon: Icons.edit_note_rounded,
        ),
        const SizedBox(height: 16),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.expense, label: Text('Gasto'), icon: Icon(Icons.remove_circle_outline_rounded)),
                    ButtonSegment(value: _Mode.income, label: Text('Ingreso'), icon: Icon(Icons.add_circle_outline_rounded)),
                    ButtonSegment(value: _Mode.transfer, label: Text('Transfer'), icon: Icon(Icons.swap_horiz_rounded)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
                const SizedBox(height: 12),
                DsInput(
                  controller: _amount,
                  label: 'Monto',
                  icon: Icons.attach_money_rounded,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (n == null || n <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DsInput(
                  controller: _title,
                  label: isTransfer ? 'Concepto (opcional)' : 'Concepto',
                  icon: Icons.edit_note_rounded,
                  validator: (v) => (!isTransfer && (v == null || v.trim().isEmpty)) ? 'Ingresa un concepto' : null,
                ),
                const SizedBox(height: 12),
                if (isTransfer) ...[
                  _accountSelect('Desde', _accountId, accounts, (v) => setState(() => _accountId = v)),
                  const SizedBox(height: 12),
                  _accountSelect('Hacia', _toAccountId, accounts, (v) => setState(() => _toAccountId = v)),
                ] else ...[
                  _accountSelect('Cuenta', _accountId, accounts, (v) => setState(() => _accountId = v)),
                  const SizedBox(height: 12),
                  DsSelect<String>(
                    label: 'Categoría',
                    value: cats.any((c) => c.id == _categoryId) ? _categoryId : (cats.isNotEmpty ? cats.first.id : null),
                    icon: Icons.category_outlined,
                    items: cats.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}'))).toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  if (ref.watch(aiReadyProvider))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _suggesting ? null : () => _suggestCategory(cats),
                        icon: _suggesting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Sugerir categoría (IA)'),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                DsSelect<String>(
                  label: 'Moneda',
                  value: _currency,
                  icon: Icons.currency_exchange_rounded,
                  items: supportedCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _currency = v ?? 'MXN'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(df.format(_date)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                DsInput(
                  controller: _note,
                  label: 'Nota (opcional)',
                  icon: Icons.notes_rounded,
                ),
                Builder(builder: (context) {
                  final labels = ref.watch(labelsProvider);
                  if (labels.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: labels.map((l) {
                          final sel = _labelIds.contains(l.id);
                          return FilterChip(
                            avatar: CircleAvatar(backgroundColor: l.colorValue, radius: 8),
                            label: Text(l.name),
                            selected: sel,
                            onSelected: (v) => setState(() => v ? _labelIds.add(l.id) : _labelIds.remove(l.id)),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                DsPrimaryButton(
                  onPressed: _submit,
                  icon: Icons.save_rounded,
                  label: widget.initialEntry == null ? 'Guardar movimiento' : 'Actualizar movimiento',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountSelect(String label, String? value, List<Account> accounts, ValueChanged<String?> onChanged) {
    return DsSelect<String>(
      label: label,
      value: accounts.any((a) => a.id == value) ? value : (accounts.isNotEmpty ? accounts.first.id : null),
      icon: Icons.account_balance_wallet_outlined,
      items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.icon} ${a.name}'))).toList(),
      onChanged: onChanged,
    );
  }

  Future<void> _suggestCategory(List<Category> cats) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe primero el concepto.')),
      );
      return;
    }
    final svc = ref.read(aiServicesProvider);
    if (svc == null) return;
    setState(() => _suggesting = true);
    try {
      final name = await svc.suggestCategory(title, categories: cats.map((c) => c.name).toList());
      if (name != null) {
        for (final c in cats) {
          if (c.name.toLowerCase() == name.toLowerCase()) {
            setState(() => _categoryId = c.id);
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo sugerir: $e')));
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amount.text.replaceAll(',', '.'));
    final accounts = ref.read(activeAccountsProvider);
    final cats = ref.read(activeCategoriesProvider);
    final initial = widget.initialEntry;
    final isTransfer = _mode == _Mode.transfer;

    if (isTransfer && (_accountId == null || _toAccountId == null || _accountId == _toAccountId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige dos cuentas distintas para la transferencia.')),
      );
      return;
    }

    Account? acc;
    Account? toAcc;
    for (final a in accounts) {
      if (a.id == _accountId) acc = a;
      if (a.id == _toAccountId) toAcc = a;
    }
    Category? cat;
    for (final c in cats) {
      if (c.id == _categoryId) {
        cat = c;
        break;
      }
    }

    final entry = FinanceEntry(
      id: initial?.id ?? newId('tx'),
      title: _title.text.trim().isEmpty
          ? (isTransfer ? 'Transferencia' : 'Movimiento')
          : _title.text.trim(),
      amount: amount,
      category: isTransfer ? 'Transferencia' : (cat?.name ?? 'Sin categoría'),
      categoryId: isTransfer ? null : cat?.id,
      date: _date,
      type: _mode == _Mode.income ? EntryType.income : EntryType.expense,
      account: acc?.name ?? 'Efectivo',
      accountId: acc?.id,
      currency: _currency,
      kind: isTransfer ? EntryKind.transfer : EntryKind.standard,
      transferAccountId: isTransfer ? toAcc?.id : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      exchangeRate: effectiveMxnRate(_currency),
      createdAt: initial?.createdAt,
    );

    ref.read(transactionsProvider.notifier).add(entry);
    ref.read(labelsProvider.notifier).setForTransaction(entry.id, _labelIds.toList());
    context.pop();
  }
}
