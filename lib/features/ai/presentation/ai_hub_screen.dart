import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_config.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../domain/ai_mode.dart';
import '../domain/ai_module.dart';
import 'ai_capture_sheet.dart';

/// An index of every AI module — "todo como módulos". Renders the registry
/// (`aiModulesProvider`) so AI features are discoverable from one place.
class AiHubScreen extends ConsumerWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final modules = ref.watch(aiModulesProvider);
    final ready = ref.watch(aiReadyProvider);
    final mode = ref.watch(aiModeProvider);

    return DsScreenScaffold(
      title: 'Inteligencia artificial',
      children: [
        const DsFeatureHeader(
          title: 'IA en toda la app',
          subtitle: 'Análisis, planes, sugerencias y asistente — con tus datos.',
          icon: Icons.auto_awesome_rounded,
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: ready ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready
                      ? 'IA activa · Modo ${mode.emoji} ${mode.label}'
                      : 'IA sin configurar. Toca para elegir un proveedor.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () => context.pushNamed('ai-settings'),
                child: const Text('Ajustes'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...modules.map((m) => DsListTile(
              icon: m.icon,
              title: m.title,
              subtitle: m.subtitle,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                if (m.kind == AiModuleKind.capture) {
                  showAiCaptureSheet(context, ref);
                } else if (m.routeName != null) {
                  context.pushNamed(m.routeName!);
                }
              },
            )),
      ],
    );
  }
}
