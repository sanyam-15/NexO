import 'package:flutter/material.dart';

import '../tokens/ds_radius.dart';
import '../tokens/ds_spacing.dart';

class DsStatCard extends StatelessWidget {
  const DsStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm, vertical: DsSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: DsRadius.brMd,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: DsSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
