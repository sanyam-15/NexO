import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/entity_palette.dart';
import '../../categories/domain/categories_provider.dart';
import '../domain/budget.dart';
import '../domain/budgets_provider.dart';

Future<void> showBudgetEditor(BuildContext context, WidgetRef ref, {Budget? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BudgetEditor(existing: existing),
  );
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({this.existing});
  final Budget? existing;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late BudgetPeriod _period;
  late int _color;
  late bool _includeIncome;
  late Set<String> _categories;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(text: e == null ? '' : '${e.amount}');
    _period = e?.period ?? BudgetPeriod.monthly;
    _color = e?.color ?? EntityPalette.colors[5];
    _includeIncome = e?.includeIncome ?? false;
    _categories = (e?.categoryFilter ?? const <String>[]).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
    if (name.isEmpty || amount <= 0) return;
    final notifier = ref.read(budgetsProvider.notifier);
    final filter = _categories.isEmpty ? null : _categories.toList();
    if (_isEdit) {
      notifier.save(widget.existing!.copyWith(
        name: name,
        amount: amount,
        period: _period,
        color: _color,
        includeIncome: _includeIncome,
        categoryFilter: filter,
      ));
    } else {
      notifier.create(
        name: name,
        amount: amount,
        color: _color,
        period: _period,
        includeIncome: _includeIncome,
        categoryFilter: filter,
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final cats = ref.watch(activeCategoriesProvider).where((c) => !c.isSubcategory).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Editar presupuesto' : 'Nuevo presupuesto',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Gastos del mes'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
            ),
            const SizedBox(height: 16),
            Text('Periodo', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: BudgetPeriod.values
                  .where((p) => p != BudgetPeriod.custom)
                  .map((p) => ChoiceChip(
                        label: Text(p.label),
                        selected: _period == p,
                        onSelected: (_) => setState(() => _period = p),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text('Color', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ColorSwatchPicker(selected: _color, onSelect: (c) => setState(() => _color = c)),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Presupuesto de ingresos'),
              subtitle: const Text('Mide ingresos en vez de gastos'),
              value: _includeIncome,
              onChanged: (v) => setState(() => _includeIncome = v),
            ),
            const Divider(),
            Text('Categorías (vacío = todas)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: cats.map((c) {
                final sel = _categories.contains(c.id);
                return FilterChip(
                  avatar: Text(c.emoji),
                  label: Text(c.name),
                  selected: sel,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _categories.add(c.id);
                    } else {
                      _categories.remove(c.id);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(budgetsProvider.notifier).remove(widget.existing!.id);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Eliminar'),
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
