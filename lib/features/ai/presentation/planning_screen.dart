import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/llm_client.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_section_card.dart';
import '../../../design_system/components/ds_section_title.dart';
import '../../transactions/domain/currency.dart';
import '../domain/ai_analysis.dart';
import '../domain/ai_context.dart';
import '../domain/ai_plans.dart';
import 'ai_capture_sheet.dart';
import 'ai_mode_selector.dart';
import 'ai_suggestions_card.dart';

/// The Planning workspace — the home of the AI modules. Brings together the
/// coaching Modo, the AI Análisis (health diagnosis), contextual Sugerencias,
/// generated Planes, and quick access to the assistant/capture/insights.
///
/// [embedded] renders just the scrollable body (used as the 3rd home tab);
/// otherwise it wraps itself in a Scaffold for the `/planning` route.
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  PlanType _planType = PlanType.ahorro;
  bool _generatingPlan = false;
  String? _planError;

  @override
  void initState() {
    super.initState();
    // Auto-generate the analysis when the screen opens (cached by signature).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(aiAnalysisControllerProvider.notifier).ensure();
    });
  }

  Future<void> _generatePlan() async {
    final svc = ref.read(aiPlanServiceProvider);
    if (svc == null) return;
    setState(() {
      _generatingPlan = true;
      _planError = null;
    });
    try {
      final snap = ref.read(financialSnapshotProvider);
      final plan = await svc.generatePlan(_planType, snap);
      ref.read(aiPlansProvider.notifier).save(plan);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan creado: ${plan.title}')),
        );
      }
    } on AiException catch (e) {
      if (mounted) setState(() => _planError = e.message);
    } catch (e) {
      if (mounted) setState(() => _planError = 'Algo salió mal: $e');
    } finally {
      if (mounted) setState(() => _generatingPlan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: _children(context),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Planning')),
      body: content,
    );
  }

  List<Widget> _children(BuildContext context) {
    final ready = ref.watch(aiReadyProvider);

    return [
      const DsFeatureHeader(
        title: 'Planning con IA',
        subtitle: 'Tu asesor analiza, sugiere y arma planes con tus datos.',
        icon: Icons.auto_graph_rounded,
      ),
      const SizedBox(height: 14),

      // Modo (works even before AI is configured — it's a local setting).
      const DsSectionCard(
        title: 'Modo del asesor',
        child: AiModeSelector(),
      ),
      const SizedBox(height: 14),

      if (!ready)
        DsCard(
          padding: const EdgeInsets.all(16),
          onTap: () => context.pushNamed('ai-settings'),
          child: Row(
            children: [
              Icon(Icons.key_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Configura un proveedor de IA (Anthropic, OpenAI-compatible o local) '
                  'en Ajustes → IA para activar análisis, sugerencias y planes.',
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        )
      else ...[
        const _AnalysisCard(),
        const SizedBox(height: 16),
        const AiSuggestionsCard(maxItems: 4),
        const SizedBox(height: 16),
        _PlansSection(
          planType: _planType,
          generating: _generatingPlan,
          error: _planError,
          onTypeChanged: (t) => setState(() => _planType = t),
          onGenerate: _generatePlan,
        ),
        const SizedBox(height: 16),
      ],

      _QuickAiRow(),
    ];
  }
}

class _AnalysisCard extends ConsumerWidget {
  const _AnalysisCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(aiAnalysisControllerProvider);
    final analysis = state.analysis;

    return DsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Análisis de tus finanzas',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (state.loading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  tooltip: 'Actualizar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref.read(aiAnalysisControllerProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.error != null)
            Text(state.error!, style: TextStyle(color: theme.colorScheme.error))
          else if (analysis == null && state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (analysis == null)
            Text('Toca actualizar para generar tu diagnóstico.', style: theme.textTheme.bodyMedium)
          else ...[
            Row(
              children: [
                _ScoreBadge(score: analysis.healthScore),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    analysis.headline,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (analysis.strengths.isNotEmpty)
              _AnalysisBlock(
                title: 'Fortalezas',
                icon: Icons.check_circle_rounded,
                color: theme.colorScheme.primary,
                items: analysis.strengths,
              ),
            if (analysis.risks.isNotEmpty)
              _AnalysisBlock(
                title: 'Riesgos',
                icon: Icons.warning_amber_rounded,
                color: theme.colorScheme.error,
                items: analysis.risks,
              ),
            if (analysis.opportunities.isNotEmpty)
              _AnalysisBlock(
                title: 'Oportunidades',
                icon: Icons.rocket_launch_rounded,
                color: theme.colorScheme.tertiary,
                items: analysis.opportunities,
              ),
          ],
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = score >= 70
        ? scheme.primary
        : score >= 40
            ? scheme.tertiary
            : scheme.error;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
              Text('/100', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisBlock extends StatelessWidget {
  const _AnalysisBlock({required this.title, required this.icon, required this.color, required this.items});
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: theme.textTheme.bodyMedium),
                    Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _PlansSection extends ConsumerWidget {
  const _PlansSection({
    required this.planType,
    required this.generating,
    required this.error,
    required this.onTypeChanged,
    required this.onGenerate,
  });

  final PlanType planType;
  final bool generating;
  final String? error;
  final ValueChanged<PlanType> onTypeChanged;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plans = ref.watch(aiPlansProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DsSectionTitle(title: 'Planes', icon: Icons.flag_rounded),
        const SizedBox(height: 8),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PlanType.values
                    .map((t) => ChoiceChip(
                          avatar: Text(t.emoji),
                          label: Text(t.label),
                          selected: t == planType,
                          onSelected: generating ? null : (_) => onTypeChanged(t),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: generating ? null : onGenerate,
                  icon: generating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(generating ? 'Generando…' : 'Generar ${planType.label.toLowerCase()}'),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (plans.isEmpty)
          const DsEmptyState(
            icon: Icons.flag_outlined,
            title: 'Aún no tienes planes',
            message: 'Elige un tipo y genera tu primer plan con IA.',
          )
        else
          ...plans.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlanCard(plan: p),
              )),
      ],
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});
  final FinancialPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DsCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _showPlanDetail(context, ref, plan),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(plan.type.icon, color: theme.colorScheme.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  plan.monthlyTarget != null
                      ? '${plan.type.label} · ${formatMoney(plan.monthlyTarget!)} / mes'
                      : '${plan.type.label} · ${plan.steps.length} pasos',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

void _showPlanDetail(BuildContext context, WidgetRef ref, FinancialPlan plan) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              Row(
                children: [
                  Text(plan.type.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(plan.title,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    tooltip: 'Eliminar plan',
                    onPressed: () {
                      ref.read(aiPlansProvider.notifier).remove(plan.id);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              if (plan.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(plan.summary, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (plan.monthlyTarget != null)
                    Chip(label: Text('Aporte: ${formatMoney(plan.monthlyTarget!)} / mes')),
                  if (plan.horizonMonths != null)
                    Chip(label: Text('Horizonte: ${plan.horizonMonths} meses')),
                ],
              ),
              if (plan.steps.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Pasos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...plan.steps.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              if (s.detail.isNotEmpty)
                                Text(s.detail, style: theme.textTheme.bodySmall),
                              if (s.amount != null)
                                Text(formatMoney(s.amount!),
                                    style: theme.textTheme.labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              if (plan.milestones.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Hitos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...plan.milestones.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.flag_rounded, size: 18, color: theme.colorScheme.tertiary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(m, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    )),
              ],
            ],
          );
        },
      );
    },
  );
}

class _QuickAiRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DsSectionTitle(title: 'Más IA', icon: Icons.auto_awesome_rounded),
        const SizedBox(height: 8),
        DsCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.forum_rounded),
                title: const Text('Asistente'),
                subtitle: const Text('Chatea con tu asesor financiero'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed('ai-assistant'),
              ),
              ListTile(
                leading: const Icon(Icons.tips_and_updates_rounded),
                title: const Text('Insights'),
                subtitle: const Text('Observaciones rápidas del mes'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed('ai-insights'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Captura con IA'),
                subtitle: const Text('Texto natural o foto de recibo'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showAiCaptureSheet(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.widgets_rounded),
                title: const Text('Todos los módulos'),
                subtitle: const Text('Explora las funciones de IA'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed('ai-hub'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
