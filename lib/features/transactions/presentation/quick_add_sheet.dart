import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/llm_client.dart';
import '../../../core/util/ids.dart';
import '../../../design_system/components/ds_input.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../../../design_system/components/ds_select.dart';
import '../../../design_system/tokens/ds_motion.dart';
import '../../../design_system/tokens/ds_radius.dart';
import '../../../design_system/tokens/ds_spacing.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../ai/domain/ai_providers.dart';
import '../../ai/domain/ai_services.dart';
import '../../categories/domain/categories_provider.dart';
import '../domain/capture_layout.dart';
import '../domain/capture_layout_provider.dart';
import '../domain/currency.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';

/// Parses a user-typed amount tolerating "1,234.50" / "1.234,50" / "1234,5".
double? parseAmountInput(String input) {
  final raw = input.trim().replaceAll(' ', '');
  if (raw.isEmpty) return null;
  if (raw.contains(',') && raw.contains('.')) return double.tryParse(raw.replaceAll(',', ''));
  if (raw.contains(',')) return double.tryParse(raw.replaceAll(',', '.'));
  return double.tryParse(raw);
}

/// Opens the configurable Quick Add sheet. Returns the saved entry (or null).
/// The form layout, default values and mode (manual / AI / hybrid) come from
/// [captureLayoutProvider]; categories/accounts come from the user's catalog.
Future<FinanceEntry?> showQuickAddSheet(
  BuildContext context,
  WidgetRef ref, {
  String? accountFilter,
}) {
  return showModalBottomSheet<FinanceEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QuickAddSheet(accountFilter: accountFilter),
  );
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({this.accountFilter});
  final String? accountFilter;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _aiText = TextEditingController();

  late EntryType _type;
  String? _category;
  String? _account;
  late String _currency;
  DateTime _date = DateTime.now();
  bool _paid = true;

  bool _aiLoading = false;
  String? _aiError;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(captureLayoutProvider);
    _type = cfg.defaultType;
    _currency = cfg.defaultCurrency;
    _category = cfg.defaultCategoryName;
    _account = cfg.defaultAccountName ?? widget.accountFilter;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    _aiText.dispose();
    super.dispose();
  }

  void _seedDefaults(List<String> categories, List<String> accounts) {
    if (_seeded) return;
    _seeded = true;
    _category ??= categories.isNotEmpty ? categories.first : null;
    if (_account == null || _account == 'Todas') {
      _account = accounts.isNotEmpty ? accounts.first : 'Efectivo';
    }
  }

  // ---- AI ------------------------------------------------------------------

  Future<void> _runAi(Future<ParsedTransaction> Function(AiServices svc) op) async {
    final svc = ref.read(aiServicesProvider);
    if (svc == null) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final draft = await op(svc);
      if (!mounted) return;
      _applyDraft(draft);
    } on AiException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } catch (e) {
      if (mounted) setState(() => _aiError = 'Algo salió mal: $e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  void _applyDraft(ParsedTransaction d) {
    setState(() {
      _amount.text = d.amount > 0 ? d.amount.toStringAsFixed(2) : _amount.text;
      if (d.title.trim().isNotEmpty) _title.text = d.title.trim();
      _type = d.type;
      if (d.categoryName != null) _category = d.categoryName;
      if (d.accountName != null) _account = d.accountName;
      _currency = d.currency;
      if (d.date != null) _date = d.date!;
      if (d.note != null) _note.text = d.note!;
    });
  }

  Future<void> _interpret() async {
    final text = _aiText.text.trim();
    if (text.isEmpty) return;
    final catalog = ref.read(aiCatalogProvider);
    await _runAi((svc) => svc.parseNaturalLanguage(
          text,
          categories: [for (final c in catalog.categories) c.name],
          accounts: [for (final a in catalog.accounts) a.name],
        ));
  }

  Future<void> _scanReceipt() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 1600);
    final XFile? chosen = file ?? await picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
    if (chosen == null) return;
    final bytes = await chosen.readAsBytes();
    if (!mounted) return;
    final media = chosen.mimeType ?? (chosen.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    final catalog = ref.read(aiCatalogProvider);
    await _runAi((svc) => svc.parseReceipt(
          AiImage(base64Data: base64Encode(bytes), mediaType: media),
          categories: [for (final c in catalog.categories) c.name],
        ));
  }

  // ---- save ----------------------------------------------------------------

  void _save() {
    final amount = parseAmountInput(_amount.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido para guardar')),
      );
      return;
    }
    final catalog = ref.read(aiCatalogProvider);
    final resolved = resolveCatalog(
      _category,
      _account,
      categories: catalog.categories,
      accounts: catalog.accounts,
    );
    final entry = FinanceEntry(
      id: newId('tx'),
      title: _title.text.trim().isEmpty ? (_category ?? 'Movimiento') : _title.text.trim(),
      amount: amount,
      category: resolved.category?.name ?? _category ?? 'Sin categoría',
      categoryId: resolved.category?.id,
      date: _date,
      type: _type,
      account: resolved.account?.name ?? _account ?? 'Efectivo',
      accountId: resolved.account?.id,
      currency: _currency,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      paid: _paid,
      exchangeRate: effectiveMxnRate(_currency),
      createdAt: DateTime.now(),
    );
    ref.read(transactionsProvider.notifier).add(entry);
    Navigator.pop(context, entry);
  }

  void _saveFromAiDraftOnly() {
    // AI mode with no manual fields: save straight from the parsed values.
    _save();
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(captureLayoutProvider);
    final categories = [for (final c in ref.watch(activeCategoriesProvider)) c.name];
    final accounts = [for (final a in ref.watch(activeAccountsProvider)) a.name];
    _seedDefaults(categories, accounts);
    final aiReady = ref.watch(aiReadyProvider);
    final theme = Theme.of(context);

    final showAi = cfg.quickAddMode != QuickAddMode.manual && aiReady;
    final showManual = cfg.quickAddMode != QuickAddMode.ai;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        DsSpacing.md,
        DsSpacing.xs,
        DsSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + DsSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Quick add', style: theme.textTheme.titleLarge),
                const Spacer(),
                _ModeChip(mode: cfg.quickAddMode),
              ],
            ),
            const SizedBox(height: 10),
            if (cfg.quickAddMode != QuickAddMode.manual && !aiReady)
              _AiNotConfigured(),
            if (showAi) ...[
              _AiInput(
                controller: _aiText,
                loading: _aiLoading,
                onInterpret: _aiLoading ? null : _interpret,
                onReceipt: _aiLoading ? null : _scanReceipt,
              ),
              if (_aiError != null) ...[
                const SizedBox(height: 8),
                Text(_aiError!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 14),
            ],
            if (showManual)
              ...[
                for (final field in cfg.visibleQuickFields) ...[
                  _buildField(field, categories, accounts),
                  const SizedBox(height: 10),
                ],
              ]
            else if (_aiLoading)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
            const SizedBox(height: 6),
            DsPrimaryButton(
              onPressed: showManual ? _save : _saveFromAiDraftOnly,
              icon: Icons.check_rounded,
              label: 'Guardar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(CaptureField field, List<String> categories, List<String> accounts) {
    switch (field) {
      case CaptureField.type:
        return _TypePills(
          type: _type,
          onChanged: (t) => setState(() => _type = t),
        );
      case CaptureField.amount:
        return DsInput(
          controller: _amount,
          label: 'Monto',
          icon: Icons.attach_money_rounded,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        );
      case CaptureField.title:
        return DsInput(
          controller: _title,
          label: 'Concepto (opcional)',
          icon: Icons.edit_note_rounded,
        );
      case CaptureField.category:
        final names = {if (_category != null) _category!, ...categories}.toList();
        return Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in names)
                ChoiceChip(
                  label: Text(c),
                  selected: c == _category,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
        );
      case CaptureField.account:
        final names = {if (_account != null) _account!, ...accounts, 'Efectivo'}.toList();
        // Account names are user-defined and can be arbitrarily long, so this
        // dropdown keeps isExpanded:true to ellipsize the selected value.
        // DsSelect doesn't expose isExpanded, hence the raw form field here.
        return DropdownButtonFormField<String>(
          initialValue: _account,
          isExpanded: true,
          items: [for (final a in names) DropdownMenuItem(value: a, child: Text(a))],
          onChanged: (v) => setState(() => _account = v),
          decoration: const InputDecoration(
            labelText: 'Cuenta',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
          ),
        );
      case CaptureField.currency:
        final names = {_currency, ...supportedCurrencies}.toList();
        return DsSelect<String>(
          label: 'Moneda',
          value: _currency,
          icon: Icons.currency_exchange_rounded,
          items: [for (final c in names) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _currency = v ?? _currency),
        );
      case CaptureField.date:
        return OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2015),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _date = picked);
          },
          icon: const Icon(Icons.event_rounded),
          label: Text('Fecha: ${DateFormat.yMMMd('es_MX').format(_date)}'),
        );
      case CaptureField.note:
        return DsInput(
          controller: _note,
          label: 'Nota (opcional)',
          icon: Icons.sticky_note_2_outlined,
        );
      case CaptureField.paid:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pagado'),
          subtitle: const Text('Desactiva si es un movimiento planeado'),
          value: _paid,
          onChanged: (v) => setState(() => _paid = v),
        );
    }
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});
  final QuickAddMode mode;
  @override
  Widget build(BuildContext context) {
    if (mode == QuickAddMode.manual) return const SizedBox.shrink();
    return Chip(
      avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
      label: Text(mode.label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AiNotConfigured extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const DsListTile(
      icon: Icons.key_rounded,
      title: 'Configura la IA',
      subtitle: 'Activa un proveedor en Ajustes → IA para usar el modo IA. Mientras, usa el formulario manual.',
    );
  }
}

class _AiInput extends StatelessWidget {
  const _AiInput({
    required this.controller,
    required this.loading,
    required this.onInterpret,
    required this.onReceipt,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback? onInterpret;
  final VoidCallback? onReceipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Describe el movimiento',
            hintText: 'Ej. "café 45 ayer con débito"',
            prefixIcon: Icon(Icons.auto_awesome_rounded),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: onInterpret,
                icon: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Interpretar'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onReceipt,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('Recibo'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypePills extends StatelessWidget {
  const _TypePills({required this.type, required this.onChanged});
  final EntryType type;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget pill(String label, IconData icon, EntryType value, Color bg, Color fg) {
      final selected = type == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: DsMotion.fast,
            height: 50,
            decoration: BoxDecoration(
              color: selected ? bg : scheme.surfaceContainerHigh,
              borderRadius: DsRadius.brMd,
              border: selected ? null : Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? fg : scheme.onSurfaceVariant),
                const SizedBox(width: DsSpacing.xs),
                Text(label, style: theme.textTheme.labelLarge?.copyWith(color: selected ? fg : scheme.onSurface)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill('Gasto', Icons.arrow_upward_rounded, EntryType.expense, scheme.errorContainer, scheme.onErrorContainer),
        const SizedBox(width: 10),
        pill('Ingreso', Icons.arrow_downward_rounded, EntryType.income, scheme.primaryContainer, scheme.onPrimaryContainer),
      ],
    );
  }
}
