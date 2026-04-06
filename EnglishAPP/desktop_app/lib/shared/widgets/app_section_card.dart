import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.onTap,
    this.color,
    this.gradient,
    this.borderRadius = AppRadius.lg,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double borderRadius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final content = Padding(
      padding: padding,
      child: child,
    );

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          gradient: gradient,
          borderRadius: radius,
          border: Border.all(color: borderColor ?? AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: onTap == null
            ? content
            : InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}
