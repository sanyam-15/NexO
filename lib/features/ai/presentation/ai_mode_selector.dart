import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ai_mode.dart';

/// Reusable selector for the AI coaching "Modo" (persona). Used on the Planning
/// screen and in AI settings. Picking a mode rebiases every AI module's tone;
/// since the mode is part of the analysis/suggestions cache key, the new persona
/// is applied the next time they generate (re-opening the screen or a refresh).
class AiModeSelector extends ConsumerWidget {
  const AiModeSelector({super.key, this.showDescription = true});

  final bool showDescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(aiModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: AiCoachMode.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final m = AiCoachMode.values[i];
              final selected = m == mode;
              return ChoiceChip(
                label: Text('${m.emoji} ${m.label}'),
                selected: selected,
                onSelected: (_) => ref.read(aiModeProvider.notifier).setMode(m),
              );
            },
          ),
        ),
        if (showDescription) ...[
          const SizedBox(height: 8),
          Text(
            mode.description,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
