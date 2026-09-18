import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../transactions/domain/currency.dart';
import '../domain/category.dart';
import '../domain/categories_provider.dart';
import 'category_editor.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(activeCategoriesProvider);
    final spent = ref.watch(spentByCategoryIdProvider);
    final parents = cats.where((c) => !c.isSubcategory).toList();

    return DsScreenScaffold(
      title: 'Categorías',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Categoría'),
      ),
      children: [
        const DsFeatureHeader(
          title: 'Categorías',
          subtitle: 'Organiza tus movimientos con emoji, color, tipo y subcategorías.',
          icon: Icons.category_rounded,
        ),
        const SizedBox(height: 12),
        ...parents.map((c) {
          final subs = cats.where((s) => s.parentId == c.id).toList();
          return _CategoryTile(category: c, monthSpent: spent[c.id] ?? 0, subcategories: subs, spent: spent);
        }),
      ],
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({
    required this.category,
    required this.monthSpent,
    required this.subcategories,
    required this.spent,
  });

  final Category category;
  final double monthSpent;
  final List<Category> subcategories;
  final Map<String, double> spent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InkWell(
              onTap: () => showCategoryEditor(context, ref, existing: category),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: category.colorValue.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(category.emoji, style: const TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text(category.type.label, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (monthSpent > 0)
                      Text(formatMoneyShort(monthSpent), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    IconButton(
                      tooltip: 'Agregar subcategoría',
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () => showCategoryEditor(context, ref, parentId: category.id),
                    ),
                  ],
                ),
              ),
            ),
            ...subcategories.map((s) => Padding(
                  padding: const EdgeInsets.only(left: 52, top: 2, bottom: 2),
                  child: Row(
                    children: [
                      Text(s.emoji),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.name, style: theme.textTheme.bodyMedium)),
                      if ((spent[s.id] ?? 0) > 0)
                        Text(formatMoneyShort(spent[s.id] ?? 0), style: theme.textTheme.bodySmall),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => showCategoryEditor(context, ref, existing: s),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
