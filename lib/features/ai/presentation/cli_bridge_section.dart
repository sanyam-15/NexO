import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/cli_bridge_service.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/tokens/ds_radius.dart';
import '../../../design_system/tokens/ds_spacing.dart';

/// Connect / test panel for the `cli_bridge` provider: a local OpenAI-compatible
/// bridge (in Termux) that proxies the user's Claude Code / Codex subscriptions.
///
/// Mirrors [OnDeviceSection]: it only renders state from [cliBridgeProvider]
/// (app-lifetime) and offers a health check. Reads the *live* base URL / token
/// from the settings form controllers so "Probar" tests exactly what is saved.
class CliBridgeSection extends ConsumerStatefulWidget {
  const CliBridgeSection({
    super.key,
    required this.baseUrlController,
    required this.tokenController,
  });

  final TextEditingController baseUrlController;
  final TextEditingController tokenController;

  @override
  ConsumerState<CliBridgeSection> createState() => _CliBridgeSectionState();
}

class _CliBridgeSectionState extends ConsumerState<CliBridgeSection> {
  String get _baseUrl => widget.baseUrlController.text.trim();
  String get _token => widget.tokenController.text.trim();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(cliBridgeProvider.notifier).check(_baseUrl, _token);
    });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(cliBridgeProvider);
    final ctrl = ref.read(cliBridgeProvider.notifier);

    return DsCard(
      padding: DsInsets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Bridge local (Termux)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              _StatusChip(state: state),
            ],
          ),
          const SizedBox(height: DsSpacing.xxs),
          Text(
            'Usa tus suscripciones de Claude Code y Codex a través de un bridge que corre '
            'en Termux. El modelo decide el backend: claude-* → Claude Code; gpt-*/o*/codex → Codex.',
            style: theme.textTheme.bodySmall,
          ),
          if (state.isConnected && state.backends.isNotEmpty) ...[
            const SizedBox(height: DsSpacing.sm),
            Wrap(
              spacing: DsSpacing.xs,
              runSpacing: DsSpacing.xs,
              children: [
                for (final b in state.backends)
                  Chip(
                    avatar: const Icon(Icons.check_rounded, size: 14),
                    label: Text(b, style: theme.textTheme.labelSmall),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (state.error != null && !state.isBusy) ...[
            const SizedBox(height: DsSpacing.xs),
            Text(
              state.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: DsSpacing.sm),
          Wrap(
            spacing: DsSpacing.xs,
            runSpacing: DsSpacing.xs,
            children: [
              FilledButton.icon(
                onPressed:
                    state.isBusy ? null : () => ctrl.check(_baseUrl, _token),
                icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: const Text('Probar conexión'),
              ),
            ],
          ),
          const SizedBox(height: DsSpacing.xs),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: DsSpacing.xs),
              title: Text('Cómo configurarlo (una vez)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              children: [
                _step(theme, '1',
                    'Instala Termux (F-Droid o GitHub, no Play Store).'),
                _step(
                    theme,
                    '2',
                    'Copia la carpeta tools/nexo-ai-bridge a Termux y corre el instalador. '
                        'El instalador genera token, scripts y autostart:'),
                _CopyRow(
                    label: 'Instalador', value: 'sh install.sh', onCopy: _copy),
                _step(theme, '3',
                    'Inicia sesión una vez (solo el/los que uses):'),
                _CopyRow(label: 'Login Claude', value: 'claude', onCopy: _copy),
                _CopyRow(
                    label: 'Login Codex', value: 'codex login', onCopy: _copy),
                _step(theme, '4',
                    'Arráncalo. Con Termux:Boot instalado se inicia al encender el teléfono:'),
                _CopyRow(
                    label: 'Arranque',
                    value: 'sh ~/.nexo-bridge/run.sh',
                    onCopy: _copy),
                const SizedBox(height: DsSpacing.xs),
                Divider(color: theme.dividerColor.withValues(alpha: 0.3)),
                const SizedBox(height: DsSpacing.xs),
                Text('Valores de conexión (deben coincidir con el bridge):',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
                const SizedBox(height: DsSpacing.xs),
                _CopyRow(
                  label: 'URL base',
                  value:
                      _baseUrl.isEmpty ? 'http://127.0.0.1:8787/v1' : _baseUrl,
                  onCopy: _copy,
                ),
                if (_token.isNotEmpty)
                  _CopyRow(label: 'Token', value: _token, onCopy: _copy),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(ThemeData theme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(
        top: DsSpacing.xs,
        bottom: DsSpacing.xxs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: DsSpacing.lg,
            height: DsSpacing.lg,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: DsRadius.brFull,
            ),
            child: Text(
              n,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: DsSpacing.xs),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final BridgeState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final String label;
    late final Widget avatar;
    Color? color;

    switch (state.status) {
      case BridgeStatus.connected:
        label = 'Conectado';
        avatar = Icon(Icons.check_circle_rounded,
            size: 16, color: theme.colorScheme.primary);
        color = theme.colorScheme.primary;
        break;
      case BridgeStatus.checking:
        label = 'Probando…';
        avatar = const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2));
        break;
      case BridgeStatus.disconnected:
        label = 'Sin conexión';
        avatar = Icon(Icons.cloud_off_rounded,
            size: 16, color: theme.colorScheme.error);
        color = theme.colorScheme.error;
        break;
      case BridgeStatus.unknown:
        label = 'Sin probar';
        avatar =
            Icon(Icons.help_outline_rounded, size: 16, color: theme.hintColor);
        break;
    }

    return Chip(
      avatar: avatar,
      label: Text(label,
          style: theme.textTheme.labelMedium?.copyWith(color: color)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow(
      {required this.label, required this.value, required this.onCopy});
  final String label;
  final String value;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: DsSpacing.xs,
        left: DsSpacing.xxl,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpacing.sm,
                vertical: DsSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: DsRadius.brXs,
              ),
              child: Text(
                value,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copiar $label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () => onCopy(label, value),
          ),
        ],
      ),
    );
  }
}
