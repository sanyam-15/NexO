import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/ai_provider_catalog.dart';
import '../../../core/platform/notification_access.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../capture/domain/capture_controller.dart';
import 'ai_mode_selector.dart';
import 'cli_bridge_section.dart';
import 'on_device_section.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late String _selectedId;
  late final TextEditingController _key;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(aiConfigProvider);
    _selectedId = cfg.activeId;
    _key = TextEditingController();
    _baseUrl = TextEditingController();
    _model = TextEditingController();
    _seedFrom(cfg.profile(_selectedId));
  }

  void _seedFrom(AiProviderProfile p) {
    _key.text = p.apiKey;
    _baseUrl.text = p.baseUrl;
    _model.text = p.model;
  }

  @override
  void dispose() {
    _key.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  void _onPick(String id) {
    setState(() {
      _selectedId = id;
      _seedFrom(ref.read(aiConfigProvider).profile(id));
    });
  }

  void _save(AiProviderPreset preset) {
    final notifier = ref.read(aiConfigProvider.notifier);
    notifier.updateProvider(
      _selectedId,
      apiKey: _key.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
    );
    final saved = ref.read(aiConfigProvider).profile(_selectedId);
    final messenger = ScaffoldMessenger.of(context);
    if (saved.isConfigured) {
      // Only switch the active provider (and enable AI) once it can actually
      // run — otherwise we'd silently disable a working setup.
      notifier.selectProvider(_selectedId);
      notifier.setEnabled(true);
      messenger.showSnackBar(
          SnackBar(content: Text('${preset.label} guardado y activado')));
    } else {
      messenger.showSnackBar(
        SnackBar(
            content: Text(
                '${preset.label} guardado. Completa los campos requeridos para activarlo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    final theme = Theme.of(context);
    final preset = presetById(_selectedId);
    final isActive = cfg.activeId == _selectedId;

    return DsScreenScaffold(
      title: 'Inteligencia artificial',
      children: [
        const DsFeatureHeader(
          title: 'IA en Nexo',
          subtitle:
              'Captura por lenguaje natural, escaneo de recibos, autocategorización e insights.',
          icon: Icons.auto_awesome_rounded,
        ),
        const SizedBox(height: 12),

        // ── Provider picker ───────────────────────────────────────────────
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Proveedor',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Elige Anthropic, cualquier API compatible con OpenAI, o una IA local (Ollama / LM Studio).',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedId,
                isExpanded: true,
                items: [
                  for (final p in kAiProviderPresets)
                    DropdownMenuItem(
                      value: p.id,
                      child: Row(
                        children: [
                          Icon(
                            p.isLocal
                                ? Icons.computer_rounded
                                : (p.kind == AiProviderKind.anthropic
                                    ? Icons.auto_awesome_rounded
                                    : Icons.cloud_outlined),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(p.label,
                                  overflow: TextOverflow.ellipsis)),
                          if (cfg.profile(p.id).isConfigured) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle,
                                size: 14, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => _onPick(v ?? _selectedId),
              ),
              if (preset.note != null) ...[
                const SizedBox(height: 8),
                Text(preset.note!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Credentials & model (or on-device download manager) ───────────
        if (preset.kind == AiProviderKind.onDevice)
          OnDeviceSection(profileId: _selectedId)
        else ...[
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Base URL: editable for local/custom, informational for fixed cloud.
                if (preset.kind == AiProviderKind.openai) ...[
                  if (preset.baseUrlEditable)
                    TextField(
                      controller: _baseUrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'URL base (con /v1)',
                        hintText: 'http://localhost:11434/v1',
                      ),
                    )
                  else
                    _InfoRow(label: 'Endpoint', value: preset.defaultBaseUrl),
                  const SizedBox(height: 12),
                ],

                // API key.
                TextField(
                  controller: _key,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText:
                        preset.requiresKey ? 'API key' : 'API key (opcional)',
                    hintText: preset.kind == AiProviderKind.anthropic
                        ? 'sk-ant-...'
                        : 'sk-...',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (preset.keysUrl != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    'Consigue tu key en: ${preset.keysUrl}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
                const SizedBox(height: 12),

                // Model.
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                    hintText: 'p. ej. gpt-4o-mini, gemma3, claude-haiku-4-5',
                  ),
                ),
                if (preset.modelSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in preset.modelSuggestions)
                        ActionChip(
                          label: Text(m, style: theme.textTheme.bodySmall),
                          onPressed: () => setState(() => _model.text = m),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (isActive)
                      Chip(
                        avatar: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text('Activo'),
                        visualDensity: VisualDensity.compact,
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => _save(preset),
                      child: const Text('Guardar y usar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (preset.id == 'cli_bridge') ...[
            const SizedBox(height: 12),
            CliBridgeSection(
              baseUrlController: _baseUrl,
              tokenController: _key,
            ),
          ],
        ],
        const SizedBox(height: 12),

        // ── Master switch ─────────────────────────────────────────────────
        SwitchListTile(
          title: const Text('IA activada'),
          subtitle: Text(
            cfg.isReady
                ? 'Lista para usar · ${cfg.active.label}'
                : 'Configura y guarda un proveedor para activarla',
          ),
          value: cfg.enabled,
          onChanged: cfg.active.isConfigured
              ? (v) => ref.read(aiConfigProvider.notifier).setEnabled(v)
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          cfg.active.isLocal
              ? 'Privacidad: con una IA local, el texto y las imágenes se procesan en tu propia red; '
                  'no salen a internet.'
              : 'Privacidad: al usar la IA, el texto o la imagen del movimiento se envía a ${cfg.active.label}. '
                  'El resto de tus datos permanece en el dispositivo.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // ── Modo del asesor (persona que sesga toda la IA) ────────────────
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modo del asesor',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Define el tono y las prioridades de TODA la IA: análisis, planes, sugerencias, '
                'asistente y captura.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const AiModeSelector(),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── AutoCapture (bank notifications → movements) ──────────────────
        Builder(builder: (context) {
          final pending = ref.watch(pendingCaptureCountProvider);
          final settings = ref.watch(captureSettingsProvider);
          final subtitle = !NotificationAccess.isSupported
              ? 'Solo disponible en Android'
              : (settings.enabled
                  ? 'Activada · ${settings.entityIds.length} app(s)'
                  : 'Convierte notificaciones del banco en movimientos');
          return DsListTile(
            icon: Icons.notifications_active_rounded,
            title: 'AutoCaptura por notificaciones',
            subtitle: subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pending > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$pending',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800)),
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => context.pushNamed('auto-capture'),
          );
        }),
        const SizedBox(height: 8),

        // ── Entry point to the AI module hub ──────────────────────────────
        DsListTile(
          icon: Icons.widgets_rounded,
          title: 'Módulos de IA',
          subtitle: 'Análisis, planes, sugerencias, asistente y más',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed('ai-hub'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 2),
        SelectableText(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
