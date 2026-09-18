import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/entity_palette.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../domain/label.dart';
import '../domain/labels_provider.dart';

class LabelsScreen extends ConsumerWidget {
  const LabelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(labelsProvider);

    return DsScreenScaffold(
      title: 'Etiquetas',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editLabel(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Etiqueta'),
      ),
      children: [
        const DsFeatureHeader(
          title: 'Etiquetas',
          subtitle: 'Marca movimientos con etiquetas para filtrarlos y analizarlos.',
          icon: Icons.sell_rounded,
        ),
        const SizedBox(height: 12),
        if (labels.isEmpty)
          const DsEmptyState(
            icon: Icons.sell_outlined,
            title: 'Sin etiquetas',
            message: 'Crea etiquetas como "Trabajo", "Viaje" o "Reembolsable".',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels
                .map((l) => InputChip(
                      avatar: CircleAvatar(backgroundColor: l.colorValue, radius: 8),
                      label: Text(l.name),
                      onPressed: () => _editLabel(context, ref, existing: l),
                      onDeleted: () => ref.read(labelsProvider.notifier).remove(l.id),
                    ))
                .toList(),
          ),
      ],
    );
  }

  Future<void> _editLabel(BuildContext context, WidgetRef ref, {Label? existing}) async {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    var color = existing?.color ?? EntityPalette.colors.first;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Nueva etiqueta' : 'Editar etiqueta',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 16),
              ColorSwatchPicker(selected: color, onSelect: (c) => setSheet(() => color = c)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    final name = ctrl.text.trim();
                    if (name.isEmpty) return;
                    final notifier = ref.read(labelsProvider.notifier);
                    if (existing == null) {
                      notifier.create(name: name, color: color);
                    } else {
                      notifier.save(existing.copyWith(name: name, color: color));
                    }
                    Navigator.pop(context);
                  },
                  child: Text(existing == null ? 'Crear' : 'Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
  }
}
