import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/entity_palette.dart';
import '../domain/category.dart';
import '../domain/categories_provider.dart';

Future<void> showCategoryEditor(BuildContext context, WidgetRef ref, {Category? existing, String? parentId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryEditor(existing: existing, parentId: parentId),
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.existing, this.parentId});
  final Category? existing;
  final String? parentId;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final TextEditingController _name;
  late String _emoji;
  late int _color;
  late CategoryType _type;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _emoji = e?.emoji ?? EntityPalette.categoryEmojis.first;
    _color = e?.color ?? EntityPalette.colors.first;
    _type = e?.type ?? CategoryType.expense;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final notifier = ref.read(categoriesProvider.notifier);
    if (_isEdit) {
      notifier.save(widget.existing!.copyWith(name: name, emoji: _emoji, color: _color, type: _type));
    } else {
      notifier.create(name: name, emoji: _emoji, color: _color, type: _type, parentId: widget.parentId);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Color(_color).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                  child: Text(_emoji, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.parentId != null ? 'Nueva subcategoría' : (_isEdit ? 'Editar categoría' : 'Nueva categoría'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CategoryType>(
              segments: const [
                ButtonSegment(value: CategoryType.expense, label: Text('Gasto')),
                ButtonSegment(value: CategoryType.income, label: Text('Ingreso')),
                ButtonSegment(value: CategoryType.both, label: Text('Ambos')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            Text('Color', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ColorSwatchPicker(selected: _color, onSelect: (c) => setState(() => _color = c)),
            const SizedBox(height: 16),
            Text('Emoji', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            EmojiPicker(emojis: EntityPalette.categoryEmojis, selected: _emoji, onSelect: (e) => setState(() => _emoji = e)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(categoriesProvider.notifier).archive(widget.existing!.id);
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
