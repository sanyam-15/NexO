import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/entity_palette.dart';
import '../../transactions/domain/currency.dart';
import '../domain/account.dart';
import '../domain/accounts_provider.dart';

/// Opens the create/edit account bottom sheet.
Future<void> showAccountEditor(BuildContext context, WidgetRef ref, {Account? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AccountEditor(existing: existing),
  );
}

class _AccountEditor extends ConsumerStatefulWidget {
  const _AccountEditor({this.existing});
  final Account? existing;

  @override
  ConsumerState<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<_AccountEditor> {
  late final TextEditingController _name;
  late final TextEditingController _startBalance;
  late AccountType _type;
  late String _currency;
  late int _color;
  late String _icon;
  late bool _includeInNetWorth;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _startBalance = TextEditingController(text: (e?.startingBalance ?? 0) == 0 ? '' : '${e!.startingBalance}');
    _type = e?.type ?? AccountType.cash;
    _currency = e?.currency ?? 'MXN';
    _color = e?.color ?? EntityPalette.colors.first;
    _icon = e?.icon ?? '💳';
    _includeInNetWorth = e?.includeInNetWorth ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _startBalance.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final start = double.tryParse(_startBalance.text.trim().replaceAll(',', '.')) ?? 0;
    final notifier = ref.read(accountsProvider.notifier);
    if (_isEdit) {
      notifier.save(widget.existing!.copyWith(
        name: name,
        type: _type,
        currency: _currency,
        color: _color,
        icon: _icon,
        startingBalance: start,
        includeInNetWorth: _includeInNetWorth,
      ));
    } else {
      notifier.create(
        name: name,
        type: _type,
        currency: _currency,
        color: _color,
        icon: _icon,
        startingBalance: start,
        includeInNetWorth: _includeInNetWorth,
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Editar cuenta' : 'Nueva cuenta',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. BBVA, Nu, Efectivo'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<AccountType>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: AccountType.values
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Moneda'),
                    items: supportedCurrencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v ?? _currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _startBalance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Saldo inicial', prefixText: '\$ '),
            ),
            const SizedBox(height: 16),
            Text('Color', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ColorSwatchPicker(selected: _color, onSelect: (c) => setState(() => _color = c)),
            const SizedBox(height: 16),
            Text('Ícono', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            EmojiPicker(
              emojis: EntityPalette.accountEmojis,
              selected: _icon,
              onSelect: (e) => setState(() => _icon = e),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir en patrimonio neto'),
              value: _includeInNetWorth,
              onChanged: (v) => setState(() => _includeInNetWorth = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(accountsProvider.notifier).archive(widget.existing!.id);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archivar'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(_isEdit ? 'Guardar' : 'Crear')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
