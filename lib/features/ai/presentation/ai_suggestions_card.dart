import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_config.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_section_title.dart';
import '../domain/ai_suggestions.dart';

/// Reusable contextual-suggestions widget. Auto-generates on mount and caches by
/// snapshot signature (so re-opening doesn't re-bill the provider). Embedded on
/// Home as a module and shown in full on the Planning screen.
class AiSuggestionsCard extends ConsumerStatefulWidget {
  const AiSuggestionsCard({super.key, this.maxItems = 3, this.embedded = false});

  /// Max suggestions to show.
  final int maxItems;

  /// When embedded on Home: render nothing if AI isn't configured yet.
  final bool embedded;

  @override
  ConsumerState<AiSuggestionsCard> createState() => _AiSuggestionsCardState();
}

class _AiSuggestionsCardState extends ConsumerState<AiSuggestionsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(aiSuggestionsControllerProvider.notifier).ensure();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = ref.watch(aiReadyProvider);
    final state = ref.watch(aiSuggestionsControllerProvider);

    if (!ready) {
      if (widget.embedded) return const SizedBox.shrink();
      return DsCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.pushNamed('ai-settings'),
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text('Configura un proveedor de IA para recibir sugerencias.')),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }

    final items = (state.suggestions ?? const <AiSuggestion>[]).take(widget.maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const DsSectionTitle(title: 'Sugerencias IA', icon: Icons.lightbulb_rounded),
            const Spacer(),
            if (state.loading)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                tooltip: 'Actualizar',
                visualDensity: VisualDensity.compact,
                onPressed: () => ref.read(aiSuggestionsControllerProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.error != null)
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
          )
        else if (state.loading && items.isEmpty)
          const DsCard(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Text('Sin sugerencias por ahora.', style: theme.textTheme.bodyMedium),
          )
        else
          ...items.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SuggestionTile(suggestion: s),
              )),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion});
  final AiSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = suggestion.action.routeName;
    final priorityColor = suggestion.priority == 1
        ? theme.colorScheme.error
        : suggestion.priority == 2
            ? theme.colorScheme.tertiary
            : theme.colorScheme.primary;

    return DsCard(
      padding: const EdgeInsets.all(14),
      onTap: route == null ? null : () => context.pushNamed(route),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: priorityColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(suggestion.action.icon, size: 20, color: priorityColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (suggestion.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(suggestion.body, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (route != null) const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
