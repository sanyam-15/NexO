import 'package:flutter/material.dart';

class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );

    return Card(
      margin: margin,
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              child: content,
            )
          : content,
    );
  }
}
