import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'app_section_card.dart';
import 'app_status_badge.dart';

class ArticleSummaryCard extends StatelessWidget {
  const ArticleSummaryCard({
    super.key,
    required this.title,
    required this.badgeLabel,
    required this.metadata,
    this.summary,
    this.progressPercent,
    this.progressLabel,
    this.onTap,
  });

  final String title;
  final String badgeLabel;
  final String metadata;
  final String? summary;
  final double? progressPercent;
  final String? progressLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = progressPercent == null ? null : (progressPercent! / 100).clamp(0.0, 1.0);

    return AppSectionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              AppStatusBadge(label: badgeLabel, tone: AppStatusTone.brand),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            metadata,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (summary != null && summary!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              summary!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: AppSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: AppColors.bgElevated,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              progressLabel ?? '阅读进度 ${(progressPercent ?? 0).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
