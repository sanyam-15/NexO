import 'package:flutter/material.dart';

/// Cashew-style category spending row: emoji bubble + name, a thin colored bar,
/// the "$spent / $budget" figure, and the movement count (red when over).
class CategorySpendRow extends StatelessWidget {
  const CategorySpendRow({
    super.key,
    required this.emoji,
    required this.name,
    required this.color,
    required this.fill,
    required this.amountLabel,
    required this.count,
    this.over = false,
  });

  final String emoji;
  final String name;
  final Color color;
  final double fill;
  final String amountLabel;
  final int count;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = over ? theme.colorScheme.error : color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Text(emoji, style: const TextStyle(fontSize: 19)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    ),
                    Text(
                      amountLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: over ? theme.colorScheme.error : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fill.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: barColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$count mov.', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
