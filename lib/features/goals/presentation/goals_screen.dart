import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/entity_palette.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../transactions/domain/currency.dart';
import '../domain/goal.dart';
import '../domain/goals_provider.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(activeGoalsProvider);

    return DsScreenScaffold(
      title: 'Metas de ahorro',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Meta'),
      ),
      children: [
        const DsFeatureHeader(
          title: 'Metas de ahorro',
          subtitle: 'Define objetivos, registra aportes y mira tu progreso y ritmo sugerido.',
          icon: Icons.savings_rounded,
        ),
        const SizedBox(height: 12),
        if (goals.isEmpty)
          const DsEmptyState(
            icon: Icons.flag_outlined,
            title: 'Sin metas',
            message: 'Crea una meta de ahorro y registra aportes para verla crecer.',
          )
        else
          ...goals.map((g) => _GoalCard(goal: g)),
      ],
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM yyyy', 'es_MX');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        padding: const EdgeInsets.all(16),
        onTap: () => _showGoalEditor(context, ref, existing: goal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(goal.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      if (goal.deadline != null)
                        Text('Meta: ${df.format(goal.deadline!)}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (goal.isComplete)
                  Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: goal.ratio,
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: goal.colorValue,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('${formatMoney(goal.currentAmount)} / ${formatMoney(goal.targetAmount)}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${(goal.ratio * 100).round()}%', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            if (goal.suggestedMonthly != null && !goal.isComplete) ...[
              const SizedBox(height: 6),
              Text('Aporta ~${formatMoney(goal.suggestedMonthly!)}/mes para llegar a tiempo.',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _contribute(context, ref, goal),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Aportar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _contribute(BuildContext context, WidgetRef ref, Goal goal) async {
  final ctrl = TextEditingController();
  final amount = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Aportar a ${goal.name}'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
            if (v == null || v <= 0) return;
            Navigator.pop(context, v);
          },
          child: const Text('Aportar'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (amount != null) ref.read(goalsProvider.notifier).contribute(goal.id, amount);
}

Future<void> _showGoalEditor(BuildContext context, WidgetRef ref, {Goal? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GoalEditor(existing: existing),
  );
}

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor({this.existing});
  final Goal? existing;

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late int _color;
  late String _emoji;
  DateTime? _deadline;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _target = TextEditingController(text: e == null ? '' : '${e.targetAmount}');
    _color = e?.color ?? EntityPalette.colors[9];
    _emoji = e?.emoji ?? EntityPalette.goalEmojis.first;
    _deadline = e?.deadline;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final target = double.tryParse(_target.text.trim().replaceAll(',', '.')) ?? 0;
    if (name.isEmpty || target <= 0) return;
    final notifier = ref.read(goalsProvider.notifier);
    if (_isEdit) {
      notifier.save(widget.existing!.copyWith(
        name: name,
        targetAmount: target,
        color: _color,
        emoji: _emoji,
        deadline: _deadline,
        clearDeadline: _deadline == null,
      ));
    } else {
      notifier.create(name: name, targetAmount: target, color: _color, emoji: _emoji, deadline: _deadline);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final df = DateFormat('d MMM yyyy', 'es_MX');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Editar meta' : 'Nueva meta',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Vacaciones')),
            const SizedBox(height: 12),
            TextField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monto objetivo', prefixText: '\$ ')),
            const SizedBox(height: 16),
            Text('Color', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ColorSwatchPicker(selected: _color, onSelect: (c) => setState(() => _color = c)),
            const SizedBox(height: 16),
            Text('Emoji', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            EmojiPicker(emojis: EntityPalette.goalEmojis, selected: _emoji, onSelect: (e) => setState(() => _emoji = e)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(_deadline == null ? 'Sin fecha límite' : 'Fecha límite: ${df.format(_deadline!)}'),
              trailing: _deadline == null
                  ? null
                  : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _deadline = null)),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _deadline ?? now.add(const Duration(days: 90)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 30),
                );
                if (picked != null) setState(() => _deadline = picked);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(goalsProvider.notifier).remove(widget.existing!.id);
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
