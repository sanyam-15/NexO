import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../transactions/domain/currency.dart';
import '../domain/budget.dart';

/// Circular progress ring with a centered percentage (Cashew period rings).
class BudgetRing extends StatelessWidget {
  const BudgetRing({super.key, required this.ratio, required this.color, this.size = 46});

  final double ratio;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (ratio * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '$pct%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

/// Cashew-style budget bar: a filled track with a "Hoy" pace marker positioned
/// at the elapsed fraction of the cycle, cycle-date labels at the ends, and a
/// pacing line ("disponible / por día / días restantes").
class BudgetPaceBar extends StatelessWidget {
  const BudgetPaceBar({super.key, required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final b = progress.budget;

    final ratio = progress.ratio.clamp(0.0, 1.0);
    final over = progress.isOverBudget;
    final ahead = progress.isAheadOfPace(now);
    final color = over ? scheme.error : (ahead ? Colors.orange.shade700 : b.colorValue);

    final total = progress.cycle.totalDays;
    final elapsed = progress.cycle.elapsedDays(now);
    final daysLeft = (total - elapsed).clamp(0, total);
    final markerFrac = (elapsed / total).clamp(0.0, 1.0);

    final df = DateFormat('d MMM', 'es_MX');
    final perDay = daysLeft > 0 ? progress.remaining / daysLeft : progress.remaining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 26,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final markerX = (markerFrac * w).clamp(0.0, w);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track + fill, vertically centered.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Container(height: 13, width: w, color: scheme.surfaceContainerHighest),
                          Container(height: 13, width: (ratio * w).clamp(2.0, w), color: color),
                        ],
                      ),
                    ),
                  ),
                  // "Hoy" pace marker.
                  Positioned(
                    left: markerX - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2.5, color: scheme.onSurface.withValues(alpha: 0.85)),
                  ),
                  Positioned(
                    left: (markerX - 16).clamp(0.0, w - 32),
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.onSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Hoy', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: scheme.surface)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(df.format(progress.cycle.start), style: theme.textTheme.labelSmall),
            const Spacer(),
            Text(df.format(progress.cycle.end.subtract(const Duration(days: 1))), style: theme.textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          over
              ? 'Excedido ${formatMoney(progress.spent - b.amount)}'
              : 'Disponible ${formatMoney(progress.remaining)} · ${formatMoneyShort(perDay)}/día · $daysLeft días',
          style: theme.textTheme.bodySmall?.copyWith(
            color: over ? scheme.error : (ahead ? Colors.orange.shade800 : scheme.onSurfaceVariant),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
