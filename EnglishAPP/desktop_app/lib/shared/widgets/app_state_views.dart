import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'app_section_card.dart';

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.label = '加载中...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpace.md),
          Text(label),
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpace.sm),
          Text(title, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.title = '加载失败',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 28, color: theme.colorScheme.error),
          const SizedBox(height: AppSpace.sm),
          Text(title, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpace.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
