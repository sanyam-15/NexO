import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/recurring_transactions_provider.dart';
import '../../transactions/domain/transaction.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingPaymentsProvider);
    final df = DateFormat('EEE d MMM', 'es_MX');

    Future<void> enable() async {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de notificaciones denegado.')),
          );
        }
        return;
      }
      final count = await NotificationService.scheduleReminders(upcoming);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count recordatorio(s) programado(s).')),
        );
      }
    }

    return DsScreenScaffold(
      title: 'Recordatorios',
      children: [
        const DsFeatureHeader(
          title: 'Pagos próximos',
          subtitle: 'Activa avisos en el dispositivo para no olvidar tus pagos recurrentes.',
          icon: Icons.notifications_active_rounded,
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Programa una notificación a las 9:00 del día de cada pago próximo.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: enable,
                    icon: const Icon(Icons.notifications_active_rounded, size: 18),
                    label: const Text('Activar recordatorios'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => NotificationService.showTest(),
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Probar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (upcoming.isEmpty)
          const DsEmptyState(
            icon: Icons.event_available_rounded,
            title: 'Sin pagos próximos',
            message: 'Agrega pagos recurrentes para recibir recordatorios.',
          )
        else
          ...upcoming.map((p) {
            final isExpense = p.type == EntryType.expense;
            return DsListTile(
              icon: isExpense ? Icons.south_west_rounded : Icons.north_east_rounded,
              title: p.title,
              subtitle: '${df.format(p.dueDate)} · ${p.category}',
              trailing: Text(
                formatMoney(p.amount),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            );
          }),
      ],
    );
  }
}
