import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );

    return Card(
      color: color,
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onTap,
              child: content,
            ),
    );
  }
}
