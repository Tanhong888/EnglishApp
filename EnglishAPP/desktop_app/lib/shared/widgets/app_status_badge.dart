import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

enum AppStatusTone { neutral, brand, success, warning, danger }

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppStatusTone.neutral,
  });

  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color backgroundColor;
    Color foregroundColor;

    switch (tone) {
      case AppStatusTone.brand:
        backgroundColor = AppColors.brandSoft;
        foregroundColor = AppColors.brandStrong;
        break;
      case AppStatusTone.success:
        backgroundColor = AppColors.successSoft;
        foregroundColor = AppColors.success;
        break;
      case AppStatusTone.warning:
        backgroundColor = AppColors.warningSoft;
        foregroundColor = AppColors.warning;
        break;
      case AppStatusTone.danger:
        backgroundColor = AppColors.errorSoft;
        foregroundColor = AppColors.error;
        break;
      case AppStatusTone.neutral:
        backgroundColor = AppColors.bgElevated;
        foregroundColor = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: foregroundColor),
      ),
    );
  }
}
