import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/platform/notification_access.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../categories/domain/categories_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/capture_controller.dart';
import '../domain/captured_notification.dart';
import '../domain/entity_registry.dart';

/// AutoCapture: read bank/fintech notifications and turn them into movements.
/// Money is parsed deterministically on-device; the active AI provider (which
/// can be the on-device Gemma) only suggests a category.
class AutoCaptureScreen extends ConsumerStatefulWidget {
  const AutoCaptureScreen({super.key});

  @override
  ConsumerState<AutoCaptureScreen> createState() => _AutoCaptureScreenState();
}

class _AutoCaptureScreenState extends ConsumerState<AutoCaptureScreen> with WidgetsBindingObserver {
  bool _granted = false;
  bool _checking = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user returns from the system settings screen.
    if (state == AppLifecycleState.resumed) _refreshAccess();
  }

  Future<void> _refreshAccess() async {
    final granted = await NotificationAccess.isAccessGranted();
    // If access is on, nudge the framework to (re)bind in case the listener was
    // torn down by an app update or an OEM battery manager.
    if (granted) await NotificationAccess.requestRebind();
    if (mounted) {
      setState(() {
        _granted = granted;
        _checking = false;
      });
    }
  }

  Future<void> _onConfirmNotify(bool v) async {
    await ref.read(captureSettingsProvider.notifier).setConfirmNotify(v);
    if (!v) return;
    // The confirm notification needs POST_NOTIFICATIONS (runtime on Android 13+)
    // — without it mgr.notify() is a silent no-op.
    final granted = await NotificationService.requestPermission();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Activa las notificaciones de Nexo en Ajustes del sistema para recibir las confirmaciones. '
              'Requiere Android 12 o superior.'),
        ),
      );
    }
  }

  Future<void> _processNow() async {
    setState(() => _processing = true);
    try {
      final result = await ref.read(captureInboxProvider.notifier).drainAndProcess();
      if (!mounted) return;
      final parts = <String>[];
      if (result.captured > 0) parts.add('${result.captured} capturado(s)');
      if (result.confirmed > 0) parts.add('${result.confirmed} confirmado(s)');
      if (result.dismissed > 0) parts.add('${result.dismissed} descartado(s)');
      if (result.categorized > 0) parts.add('${result.categorized} categorizado(s) con IA');
      final msg = parts.isEmpty ? 'Sin movimientos nuevos por capturar.' : '${parts.join(' · ')}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!NotificationAccess.isSupported) {
      return const DsScreenScaffold(
        title: 'AutoCaptura',
        children: [
          DsFeatureHeader(
            title: 'Solo disponible en Android',
            subtitle:
                'iOS no permite que otras apps lean tus notificaciones, así que la captura automática '
                'de movimientos solo funciona en Android.',
            icon: Icons.notifications_off_rounded,
          ),
        ],
      );
    }

    final settings = ref.watch(captureSettingsProvider);
    final pending = ref.watch(captureInboxProvider);
    final theme = Theme.of(context);

    return DsScreenScaffold(
      title: 'AutoCaptura',
      children: [
        const DsFeatureHeader(
          title: 'Captura por notificaciones',
          subtitle:
              'Lee las notificaciones de tus apps bancarias y crea los movimientos por ti. El monto se '
              'detecta en el dispositivo; si tienes Gemma on-device activo, también sugiere la categoría '
              '— sin enviar el texto a la nube. Con otro proveedor, eliges la categoría al confirmar.',
          icon: Icons.notifications_active_rounded,
        ),
        const SizedBox(height: 12),

        // ── Access status ────────────────────────────────────────────────
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _granted ? Icons.verified_user_rounded : Icons.lock_outline_rounded,
                    color: _granted ? Colors.green : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _checking
                          ? 'Comprobando acceso…'
                          : (_granted
                              ? 'Acceso a notificaciones concedido'
                              : 'Falta el permiso de acceso a notificaciones'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Nexo necesita el permiso especial de "Acceso a notificaciones" para leer los avisos de '
                'tus apps de banco. Solo se procesan las apps que actives abajo; nada sale del dispositivo.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => NotificationAccess.openAccessSettings(),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: Text(_granted ? 'Abrir ajustes' : 'Conceder acceso'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _refreshAccess,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Comprobar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Master switch ────────────────────────────────────────────────
        SwitchListTile(
          title: const Text('Captura automática'),
          subtitle: Text(
            settings.enabled
                ? 'Activada · ${settings.entityIds.length} app(s) en la lista'
                : 'Apagada',
          ),
          value: settings.enabled,
          onChanged: (v) => ref.read(captureSettingsProvider.notifier).setEnabled(v),
        ),
        const SizedBox(height: 4),

        // ── Confirm-by-notification + discovery ───────────────────────────
        DsCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                dense: true,
                title: const Text('Confirmar con notificación'),
                subtitle: Text(
                  'Cuando llegue un movimiento nuevo o de formato desconocido, Nexo te manda una '
                  'notificación "¿Registrar movimiento?" y lo confirmas con tu huella sin abrir la app.',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: true,
                value: settings.confirmNotify,
                onChanged: settings.enabled ? _onConfirmNotify : null,
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Descubrir apps nuevas'),
                subtitle: Text(
                  'Detecta movimientos de apps que aún no están en tu lista para proponerte registrarlas. '
                  'Observa notificaciones de otras apps (más exposición de privacidad).',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: true,
                value: settings.discovery,
                onChanged: settings.enabled
                    ? (v) => ref.read(captureSettingsProvider.notifier).setDiscovery(v)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Allowlist of finance apps ────────────────────────────────────
        DsCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: Text('Apps a capturar',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              for (final e in kCaptureEntities)
                SwitchListTile(
                  dense: true,
                  title: Text(e.name),
                  subtitle: Text(e.type.label, style: theme.textTheme.bodySmall),
                  value: settings.isEntityEnabled(e.id),
                  onChanged: settings.enabled
                      ? (v) => ref.read(captureSettingsProvider.notifier).toggleEntity(e.id, v)
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Process now ──────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _processing ? null : _processNow,
                icon: _processing
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(_processing ? 'Procesando…' : 'Procesar ahora'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Review inbox ─────────────────────────────────────────────────
        Text('Por revisar (${pending.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const DsEmptyState(
            icon: Icons.inbox_rounded,
            title: 'Nada por revisar',
            message:
                'Cuando llegue una notificación de una app activada, pulsa "Procesar ahora" y aparecerá aquí.',
          )
        else
          ...pending.map((c) => _CaptureTile(
                key: ValueKey(c.id),
                item: c,
                onConfirm: (category, userChose) => _confirm(c, category, userChose),
                onDismiss: () => ref.read(captureInboxProvider.notifier).dismiss(c.id),
              )),
      ],
    );
  }

  Future<void> _confirm(CapturedNotification c, String? category, bool userChose) async {
    var amount = c.amount;
    if (amount == null || amount <= 0) {
      amount = await _askAmount(c);
      if (amount == null) return; // cancelled
    }
    ref.read(captureInboxProvider.notifier).confirm(
          c,
          amountOverride: amount,
          categoryOverride: category,
          // Learn the merchant→category rule only from an explicit user pick.
          learn: userChose,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(category != null ? 'Agregado en $category.' : 'Movimiento agregado.')),
      );
    }
  }

  Future<double?> _askAmount(CapturedNotification c) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Falta el monto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Monto (MXN)', prefixText: '\$ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.replaceAll(',', '').trim());
              Navigator.pop(ctx, v != null && v > 0 ? v : null);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }
}

class _CaptureTile extends ConsumerStatefulWidget {
  const _CaptureTile({super.key, required this.item, required this.onConfirm, required this.onDismiss});

  final CapturedNotification item;

  /// Confirms with the chosen category (null = uncategorized). [userChose] is
  /// true only when the user explicitly picked it (vs. accepting the suggestion),
  /// which is what teaches the merchant→category memory.
  final void Function(String? category, bool userChose) onConfirm;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_CaptureTile> createState() => _CaptureTileState();
}

class _CaptureTileState extends ConsumerState<_CaptureTile> {
  late String? _category = widget.item.suggestedCategory;
  bool _userChose = false;

  @override
  void didUpdateWidget(_CaptureTile old) {
    super.didUpdateWidget(old);
    // If this tile is reused for a different capture, reset the picked category.
    if (old.item.id != widget.item.id) {
      _category = widget.item.suggestedCategory;
      _userChose = false;
    }
  }

  Future<void> _pickCategory() async {
    final categories = ref.read(activeCategoriesProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: categories.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aún no tienes categorías. Créalas en Ajustes → Categorías.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final c in categories)
                    ListTile(
                      leading: Text(c.emoji, style: const TextStyle(fontSize: 20)),
                      title: Text(c.name),
                      trailing: _category == c.name ? const Icon(Icons.check_rounded) : null,
                      onTap: () => Navigator.pop(ctx, c.name),
                    ),
                ],
              ),
      ),
    );
    if (picked != null) {
      setState(() {
        _category = picked;
        _userChose = true; // an explicit pick → teach the memory on confirm
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final isIncome = item.direction == EntryType.income;
    final df = DateFormat('d MMM, HH:mm', 'es_MX');
    // A capture with no catalog entity came from discovery of an unknown app —
    // lower trust: badge it and don't surface its raw notification body.
    final discovered = item.entityType == null;

    return DsCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isIncome ? Icons.north_east_rounded : Icons.south_west_rounded,
                  color: isIncome ? Colors.green : theme.colorScheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.displayTitle,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text(
                item.hasAmount ? formatMoney(item.amount!) : 'Sin monto',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: item.hasAmount ? null : theme.hintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (discovered) _chip(theme, 'Descubierto', icon: Icons.travel_explore_rounded),
              _chip(theme, item.entityName ?? item.package),
              if (item.cardLast4 != null) _chip(theme, '••${item.cardLast4}'),
              _chip(theme, df.format(item.postedAt)),
            ],
          ),
          const SizedBox(height: 8),
          // Category: pre-filled from the learned memory / AI; one tap to change.
          InkWell(
            onTap: _pickCategory,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.label_outline_rounded, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _category ?? 'Elegir categoría',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _category == null ? theme.hintColor : null,
                      ),
                    ),
                  ),
                  if (_category != null && _category == item.suggestedCategory)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.auto_awesome_rounded, size: 14, color: theme.colorScheme.primary),
                    ),
                  const Icon(Icons.expand_more_rounded, size: 18),
                ],
              ),
            ),
          ),
          if (discovered) ...[
            const SizedBox(height: 6),
            Text('App nueva — revisa la cuenta antes de agregar.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ] else if (item.text != null && item.text!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.text!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: widget.onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Descartar'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: () => widget.onConfirm(_category, _userChose),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: theme.colorScheme.primary), const SizedBox(width: 3)],
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
