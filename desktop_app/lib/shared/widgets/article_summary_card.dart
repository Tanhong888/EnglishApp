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
      padding: const EdgeInsets.all(AppSpace.lg),
      gradient: LinearGradient(
        colors: <Color>[
          AppColors.surface,
          AppColors.surfaceMuted.withValues(alpha: 0.96),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.brandStrong,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusBadge(label: badgeLabel, tone: AppStatusTone.brand),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      metadata,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpace.sm),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.arrow_outward_rounded,
                    size: 18,
                    color: AppColors.brandStrong,
                  ),
                ),
              ],
            ],
          ),
          if (summary != null && summary!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              summary!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Text(
            progress == null
                ? '点击卡片进入阅读，开始今天的桌面学习。'
                : (progressLabel ?? '阅读进度 ${(progressPercent ?? 0).toStringAsFixed(0)}%'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpace.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: AppColors.bgElevated,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
