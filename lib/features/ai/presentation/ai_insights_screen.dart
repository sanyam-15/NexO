import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/llm_client.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../domain/ai_context.dart';
import '../domain/ai_providers.dart';

class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  bool _loading = false;
  String? _error;
  List<String>? _insights;

  Future<void> _generate() async {
    final svc = ref.read(aiServicesProvider);
    if (svc == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await svc.generateInsights(ref.read(financialSnapshotProvider).toPromptText());
      setState(() => _insights = result);
    } on AiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Algo salió mal: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(aiReadyProvider);
    final theme = Theme.of(context);

    return DsScreenScaffold(
      title: 'Insights con IA',
      children: [
        const DsFeatureHeader(
          title: 'Coach financiero',
          subtitle: 'Observaciones accionables a partir de tus gastos y presupuestos.',
          icon: Icons.tips_and_updates_rounded,
        ),
        const SizedBox(height: 12),
        if (!ready)
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Configura un proveedor de IA en Ajustes → IA para generar insights.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          FilledButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(_insights == null ? 'Generar insights' : 'Regenerar'),
          ),
          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_insights != null) ...[
            const SizedBox(height: 14),
            ..._insights!.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DsCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(i, style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ],
    );
  }
}
