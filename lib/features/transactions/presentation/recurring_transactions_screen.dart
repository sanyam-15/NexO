import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_input.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../../design_system/components/ds_select.dart';
import '../domain/recurring_transaction.dart';
import '../domain/recurring_transactions_provider.dart';
import '../domain/transaction.dart';

class RecurringTransactionsScreen extends ConsumerStatefulWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  ConsumerState<RecurringTransactionsScreen> createState() => _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState extends ConsumerState<RecurringTransactionsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();

  String _category = 'Comida';
  EntryType _type = EntryType.expense;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  int _monthlyDay = 1;
  int _weeklyDay = DateTime.monday;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recurring = ref.watch(recurringTransactionsProvider);
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

    return DsScreenScaffold(
      title: 'Pagos recurrentes',
      children: [
          const DsFeatureHeader(
            title: 'Pagos recurrentes',
            subtitle: 'Automatiza tus cobros y pagos frecuentes con menos fricción.',
            icon: Icons.repeat_rounded,
          ),
          const SizedBox(height: 12),
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nuevo recurrente', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Plantillas rápidas', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _templates
                        .map(
                          (t) => ActionChip(
                            avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
                            label: Text(t.label),
                            onPressed: () => _applyTemplate(t),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  DsInput(
                    controller: _title,
                    label: 'Concepto',
                    icon: Icons.edit_note_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un concepto' : null,
                  ),
                  const SizedBox(height: 10),
                  DsInput(
                    controller: _amount,
                    label: 'Monto',
                    icon: Icons.attach_money_rounded,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Monto inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DsSelect<String>(
                    value: _category,
                    label: 'Categoría',
                    icon: Icons.category_outlined,
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v ?? 'Comida'),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<EntryType>(
                    segments: const [
                      ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
                      ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => setState(() => _type = v.first),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<RecurringFrequency>(
                    segments: const [
                      ButtonSegment(value: RecurringFrequency.monthly, label: Text('Mensual')),
                      ButtonSegment(value: RecurringFrequency.weekly, label: Text('Semanal')),
                    ],
                    selected: {_frequency},
                    onSelectionChanged: (v) => setState(() => _frequency = v.first),
                  ),
                  const SizedBox(height: 10),
                  if (_frequency == RecurringFrequency.monthly)
                    DsSelect<int>(
                      value: _monthlyDay,
                      label: 'Día de cobro/pago',
                      icon: Icons.calendar_month_rounded,
                      items: List.generate(31, (i) => i + 1)
                          .map((d) => DropdownMenuItem(value: d, child: Text('Día $d del mes')))
                          .toList(),
                      onChanged: (v) => setState(() => _monthlyDay = v ?? 1),
                    )
                  else
                    DsSelect<int>(
                      value: _weeklyDay,
                      label: 'Día de la semana',
                      icon: Icons.event_repeat_rounded,
                      items: const [
                        DropdownMenuItem(value: DateTime.monday, child: Text('Lunes')),
                        DropdownMenuItem(value: DateTime.tuesday, child: Text('Martes')),
                        DropdownMenuItem(value: DateTime.wednesday, child: Text('Miércoles')),
                        DropdownMenuItem(value: DateTime.thursday, child: Text('Jueves')),
                        DropdownMenuItem(value: DateTime.friday, child: Text('Viernes')),
                        DropdownMenuItem(value: DateTime.saturday, child: Text('Sábado')),
                        DropdownMenuItem(value: DateTime.sunday, child: Text('Domingo')),
                      ],
                      onChanged: (v) => setState(() => _weeklyDay = v ?? DateTime.monday),
                    ),
                  const SizedBox(height: 14),
                  DsPrimaryButton(
                    onPressed: _save,
                    icon: Icons.repeat_rounded,
                    label: 'Guardar recurrente',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Recurrentes activos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (recurring.isEmpty)
            const DsEmptyState(
              icon: Icons.repeat_rounded,
              title: 'Sin recurrentes activos',
              message: 'Aún no tienes pagos recurrentes.',
            )
          else
            ...recurring.map((r) {
              final isExpense = r.type == EntryType.expense;
              return DsListTile(
                icon: isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                title: r.title,
                subtitle:
                    '${r.category} · ${r.frequency == RecurringFrequency.monthly ? 'Mensual día ${r.dayOfMonth ?? 1}' : 'Semanal ${_weekdayLabel(r.dayOfWeek ?? DateTime.monday)}'}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${isExpense ? '-' : '+'}${money.format(r.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isExpense ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _openEditDialog(r),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar',
                    ),
                    IconButton(
                      onPressed: () => ref.read(recurringTransactionsProvider.notifier).remove(r.id),
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Eliminar',
                    ),
                  ],
                ),
              );
            }),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final nextDate = _computeNextDueDate(
      frequency: _frequency,
      monthlyDay: _monthlyDay,
      weeklyDay: _weeklyDay,
    );

    ref.read(recurringTransactionsProvider.notifier).add(
          RecurringTransaction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: _title.text.trim(),
            amount: double.parse(_amount.text),
            category: _category,
            type: _type,
            frequency: _frequency,
            dayOfMonth: _frequency == RecurringFrequency.monthly ? _monthlyDay : null,
            dayOfWeek: _frequency == RecurringFrequency.weekly ? _weeklyDay : null,
            nextDueDate: nextDate,
          ),
        );

    _title.clear();
    _amount.clear();
    final nextText = DateFormat.yMMMd('es_MX').format(nextDate);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recurrente guardado. Próximo: $nextText')),
    );
  }

  Future<void> _openEditDialog(RecurringTransaction item) async {
    final titleCtrl = TextEditingController(text: item.title);
    final amountCtrl = TextEditingController(text: item.amount.toStringAsFixed(2));

    String category = item.category;
    EntryType type = item.type;
    RecurringFrequency frequency = item.frequency;
    int monthlyDay = item.dayOfMonth ?? item.nextDueDate.day;
    int weeklyDay = item.dayOfWeek ?? item.nextDueDate.weekday;

    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<RecurringTransaction>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Editar recurrente'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Concepto'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un concepto' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Monto'),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Monto inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setModalState(() => category = v ?? category),
                        decoration: const InputDecoration(labelText: 'Categoría'),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<EntryType>(
                        segments: const [
                          ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
                          ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
                        ],
                        selected: {type},
                        onSelectionChanged: (v) => setModalState(() => type = v.first),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<RecurringFrequency>(
                        segments: const [
                          ButtonSegment(value: RecurringFrequency.monthly, label: Text('Mensual')),
                          ButtonSegment(value: RecurringFrequency.weekly, label: Text('Semanal')),
                        ],
                        selected: {frequency},
                        onSelectionChanged: (v) => setModalState(() => frequency = v.first),
                      ),
                      const SizedBox(height: 10),
                      if (frequency == RecurringFrequency.monthly)
                        DropdownButtonFormField<int>(
                          initialValue: monthlyDay,
                          items: List.generate(31, (i) => i + 1)
                              .map((d) => DropdownMenuItem(value: d, child: Text('Día $d del mes')))
                              .toList(),
                          onChanged: (v) => setModalState(() => monthlyDay = v ?? monthlyDay),
                          decoration: const InputDecoration(labelText: 'Día de cobro/pago'),
                        )
                      else
                        DropdownButtonFormField<int>(
                          initialValue: weeklyDay,
                          items: const [
                            DropdownMenuItem(value: DateTime.monday, child: Text('Lunes')),
                            DropdownMenuItem(value: DateTime.tuesday, child: Text('Martes')),
                            DropdownMenuItem(value: DateTime.wednesday, child: Text('Miércoles')),
                            DropdownMenuItem(value: DateTime.thursday, child: Text('Jueves')),
                            DropdownMenuItem(value: DateTime.friday, child: Text('Viernes')),
                            DropdownMenuItem(value: DateTime.saturday, child: Text('Sábado')),
                            DropdownMenuItem(value: DateTime.sunday, child: Text('Domingo')),
                          ],
                          onChanged: (v) => setModalState(() => weeklyDay = v ?? weeklyDay),
                          decoration: const InputDecoration(labelText: 'Día de la semana'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;

                    final frequencyValue = frequency;
                    final nextDate = _computeNextDueDate(
                      frequency: frequencyValue,
                      monthlyDay: monthlyDay,
                      weeklyDay: weeklyDay,
                    );

                    Navigator.pop(
                      context,
                      RecurringTransaction(
                        id: item.id,
                        title: titleCtrl.text.trim(),
                        amount: double.parse(amountCtrl.text),
                        category: category,
                        type: type,
                        frequency: frequencyValue,
                        dayOfMonth: frequencyValue == RecurringFrequency.monthly ? monthlyDay : null,
                        dayOfWeek: frequencyValue == RecurringFrequency.weekly ? weeklyDay : null,
                        nextDueDate: nextDate,
                        active: true,
                      ),
                    );
                  },
                  child: const Text('Guardar cambios'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (updated != null) {
      ref.read(recurringTransactionsProvider.notifier).add(updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recurrente actualizado')));
    }
  }

  DateTime _computeNextDueDate({
    required RecurringFrequency frequency,
    required int monthlyDay,
    required int weeklyDay,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (frequency == RecurringFrequency.monthly) {
      var candidate = _safeMonthlyDate(today.year, today.month, monthlyDay);
      if (candidate.isBefore(today)) {
        candidate = _safeMonthlyDate(today.year, today.month + 1, monthlyDay);
      }
      return candidate;
    }

    final delta = (weeklyDay - today.weekday) % 7;
    final safeDelta = delta == 0 ? 7 : delta;
    return today.add(Duration(days: safeDelta));
  }

  DateTime _safeMonthlyDate(int year, int month, int desiredDay) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = desiredDay.clamp(1, lastDay);
    return DateTime(year, month, safeDay);
  }

  void _applyTemplate(_RecurringTemplate t) {
    setState(() {
      _title.text = t.title;
      _amount.text = t.amount.toStringAsFixed(t.amount.truncateToDouble() == t.amount ? 0 : 2);
      _category = t.category;
      _type = t.type;
      _frequency = t.frequency;
      _monthlyDay = t.dayOfMonth ?? _monthlyDay;
      _weeklyDay = t.dayOfWeek ?? _weeklyDay;
    });
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lunes';
      case DateTime.tuesday:
        return 'Martes';
      case DateTime.wednesday:
        return 'Miércoles';
      case DateTime.thursday:
        return 'Jueves';
      case DateTime.friday:
        return 'Viernes';
      case DateTime.saturday:
        return 'Sábado';
      case DateTime.sunday:
        return 'Domingo';
      default:
        return 'Lunes';
    }
  }
}

class _RecurringTemplate {
  const _RecurringTemplate({
    required this.label,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.frequency,
    this.dayOfMonth,
    this.dayOfWeek,
  });

  final String label;
  final String title;
  final double amount;
  final String category;
  final EntryType type;
  final RecurringFrequency frequency;
  final int? dayOfMonth;
  final int? dayOfWeek;
}

const _categories = ['Comida', 'Transporte', 'Casa', 'Salud', 'Ocio', 'Ingresos'];

const _templates = [
  _RecurringTemplate(
    label: 'Renta',
    title: 'Renta',
    amount: 8500,
    category: 'Casa',
    type: EntryType.expense,
    frequency: RecurringFrequency.monthly,
    dayOfMonth: 1,
  ),
  _RecurringTemplate(
    label: 'Spotify',
    title: 'Spotify Premium',
    amount: 129,
    category: 'Ocio',
    type: EntryType.expense,
    frequency: RecurringFrequency.monthly,
    dayOfMonth: 15,
  ),
  _RecurringTemplate(
    label: 'Gym',
    title: 'Gym',
    amount: 180,
    category: 'Salud',
    type: EntryType.expense,
    frequency: RecurringFrequency.weekly,
    dayOfWeek: DateTime.monday,
  ),
  _RecurringTemplate(
    label: 'Nómina',
    title: 'Nómina',
    amount: 12000,
    category: 'Ingresos',
    type: EntryType.income,
    frequency: RecurringFrequency.monthly,
    dayOfMonth: 15,
  ),
];
