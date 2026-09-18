import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/on_device_models.dart';
import '../../../design_system/components/ds_card.dart';
import '../domain/on_device_download_controller.dart';

/// Manages downloading, selecting and deleting on-device Gemma models for the
/// `gemma_device` provider. All download/progress state lives in
/// [onDeviceDownloadProvider] (app-lifetime), so it survives navigation,
/// screen-off and rebuilds — this widget only renders it.
class OnDeviceSection extends ConsumerStatefulWidget {
  const OnDeviceSection({super.key, required this.profileId});

  final String profileId;

  @override
  ConsumerState<OnDeviceSection> createState() => _OnDeviceSectionState();
}

class _OnDeviceSectionState extends ConsumerState<OnDeviceSection> {
  late final TextEditingController _token;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: ref.read(aiConfigProvider).profile(widget.profileId).apiKey);
    // Re-check installed state when the section opens.
    Future.microtask(() => ref.read(onDeviceDownloadProvider.notifier).refreshInstalled());
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _persistToken() {
    ref.read(aiConfigProvider.notifier).updateProvider(widget.profileId, apiKey: _token.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloads = ref.watch(onDeviceDownloadProvider);
    final notifier = ref.read(onDeviceDownloadProvider.notifier);
    final activeModel = ref.watch(aiConfigProvider).profile(widget.profileId).model;

    // Token only matters for gated models; the default Gemma 4 builds are public.
    final needsToken = kOnDeviceModels.any((m) => m.needsAuth);
    final token = needsToken ? _token.text.trim() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (needsToken) ...[
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Token de Hugging Face',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Algunos modelos están protegidos: acepta su licencia en huggingface.co y pega un '
                  'token de lectura. Solo se usa para descargar; la inferencia es 100% offline.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _token,
                  obscureText: _obscureToken,
                  onSubmitted: (_) => _persistToken(),
                  decoration: InputDecoration(
                    labelText: 'hf_...',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('Modelos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final model in kOnDeviceModels) ...[
          _ModelTile(
            model: model,
            state: downloads[model.id] ?? const ModelDownloadState(DownloadPhase.idle),
            isActive: activeModel == model.id,
            onDownload: () => notifier.start(model, token: token),
            onImport: () => notifier.import(model),
            onCancel: () => notifier.cancel(model.id),
            onUse: () => notifier.activate(model.id),
            onDelete: () => notifier.remove(model.id),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.state,
    required this.isActive,
    required this.onDownload,
    required this.onImport,
    required this.onCancel,
    required this.onUse,
    required this.onDelete,
  });

  final OnDeviceModel model;
  final ModelDownloadState state;
  final bool isActive;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onCancel;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(model.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (isActive && state.phase == DownloadPhase.installed)
                Chip(
                  avatar: const Icon(Icons.bolt_rounded, size: 14),
                  label: const Text('Activo'),
                  visualDensity: VisualDensity.compact,
                )
              else if (state.phase == DownloadPhase.installed)
                Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(model.sizeLabel, style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor)),
              if (model.supportsVision) ...[
                const SizedBox(width: 8),
                Icon(Icons.image_outlined, size: 14, color: theme.hintColor),
              ],
            ],
          ),
          if (model.note != null) ...[
            const SizedBox(height: 4),
            Text(model.note!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          _actions(theme),
        ],
      ),
    );
  }

  Widget _actions(ThemeData theme) {
    switch (state.phase) {
      case DownloadPhase.downloading:
        return Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: state.percent / 100)),
            const SizedBox(width: 10),
            Text('${state.percent}%', style: theme.textTheme.labelMedium),
            const SizedBox(width: 6),
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
          ],
        );
      case DownloadPhase.resumable:
        return Row(
          children: [
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Reanudar descarga'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Descartar'),
            ),
          ],
        );
      case DownloadPhase.importable:
        return Row(
          children: [
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.drive_folder_upload_rounded, size: 18),
              label: const Text('Importar archivo local'),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Detectado en el dispositivo',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            ),
          ],
        );
      case DownloadPhase.installing:
        return Row(
          children: const [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Importando…'),
          ],
        );
      case DownloadPhase.installed:
        return Row(
          children: [
            if (!isActive) FilledButton.tonal(onPressed: onUse, child: const Text('Usar')),
            const Spacer(),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Eliminar'),
            ),
          ],
        );
      case DownloadPhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
              ),
            ),
          ],
        );
      case DownloadPhase.idle:
        return Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar'),
          ),
        );
    }
  }
}
