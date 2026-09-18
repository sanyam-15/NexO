import 'package:flutter/material.dart';

import '../tokens/ds_spacing.dart';

class DsSectionTitle extends StatelessWidget {
  const DsSectionTitle({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm, vertical: DsSpacing.xs - 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: DsSpacing.xs - 2),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
