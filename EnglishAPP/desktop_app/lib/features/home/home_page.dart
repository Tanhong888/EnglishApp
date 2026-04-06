import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';
import '../../shared/widgets/article_summary_card.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHome();
  }

  Future<Map<String, dynamic>> _loadHome() async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    final recommendations = await api.get('/home/recommendations');
    var recentItems = <Map<String, dynamic>>[];

    if (session.isAuthenticated) {
      try {
        final recent = await api.get('/reading/recent', requiresAuth: true);
        final rawRecent = (recent['data'] as List?)?.cast<Map>() ?? const <Map>[];
        recentItems = rawRecent.map((item) => item.cast<String, dynamic>()).toList();
      } catch (_) {
        recentItems = <Map<String, dynamic>>[];
      }
    }

    return {
      'recommendations': (recommendations['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      'recent': recentItems,
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadHome();
    });
    await _future;
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.xs),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );

    if (actionLabel == null || onAction == null) {
      return info;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              info,
              const SizedBox(height: AppSpace.sm),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: info),
            const SizedBox(width: AppSpace.md),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        );
      },
    );
  }

  Widget _buildArticleCard(BuildContext context, Map<String, dynamic> item) {
    final articleId = (item['id'] as num?)?.toInt() ?? (item['article_id'] as num?)?.toInt() ?? 0;
    final title = item['title']?.toString() ?? 'Untitled';
    final stage = item['stage']?.toString() ?? '-';
    final topic = item['topic']?.toString() ?? '-';
    final minutes = item['reading_minutes']?.toString() ?? '-';
    final summary = item['summary']?.toString();
    final progress = (item['progress_percent'] as num?)?.toDouble();

    return ArticleSummaryCard(
      title: title,
      badgeLabel: '$stage · ${minutes}min',
      metadata: '主题：$topic',
      summary: summary,
      progressPercent: progress,
      progressLabel: progress == null ? null : '继续阅读 ${progress.toStringAsFixed(0)}%',
      onTap: articleId <= 0 ? null : () => context.push('/articles/$articleId'),
    );
  }

  Widget _buildArticleWrap(BuildContext context, List<Map<String, dynamic>> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 980 ? 2 : 1;
        final spacing = AppSpace.md;
        final itemWidth = columnCount == 1 ? constraints.maxWidth : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _buildArticleCard(context, item),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeroPanel(
    BuildContext context, {
    required String nickname,
    required bool isAuthenticated,
    required List<Map<String, dynamic>> today,
    required List<Map<String, dynamic>> recent,
  }) {
    final theme = Theme.of(context);

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStatusBadge(
          label: isAuthenticated ? '同步中的学习桌面' : '访客学习桌面',
          tone: isAuthenticated ? AppStatusTone.brand : AppStatusTone.neutral,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          '你好，$nickname',
          style: AppTheme.kaitiTextStyle(
            theme.textTheme.headlineSmall,
            fontSize: 36,
            height: 1.15,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          '把首页变成一张温暖的学习桌面：从推荐短文开始，边读边点词，把今天的节奏铺开。',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpace.lg),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            _HeroMetric(
              icon: Icons.wb_sunny_outlined,
              label: '今日推荐',
              value: '${today.length} 篇',
            ),
            _HeroMetric(
              icon: Icons.history_edu_outlined,
              label: '继续阅读',
              value: isAuthenticated ? '${recent.length} 条' : '登录后同步',
            ),
            _HeroMetric(
              icon: Icons.bookmark_outline_rounded,
              label: '学习方式',
              value: '点词即收藏',
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton.icon(
              onPressed: () => context.push('/articles'),
              icon: const Icon(Icons.auto_stories_outlined),
              label: const Text('开始浏览文章'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/vocab'),
              icon: const Icon(Icons.bookmark_outline),
              label: const Text('打开生词本'),
            ),
            if (!isAuthenticated)
              OutlinedButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login),
                label: const Text('登录同步进度'),
              ),
          ],
        ),
      ],
    );

    final sidePanel = Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('桌面便签', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpace.md),
          _DeskChecklistItem(
            icon: Icons.auto_awesome_outlined,
            title: '先选一篇轻量短文热身',
            subtitle: '推荐区已经为你准备了适合开始阅读的文章。',
          ),
          const SizedBox(height: AppSpace.md),
          _DeskChecklistItem(
            icon: Icons.touch_app_outlined,
            title: '阅读时随手点词',
            subtitle: '重点词汇可以直接进入生词本，后面集中整理。',
          ),
          const SizedBox(height: AppSpace.md),
          _DeskChecklistItem(
            icon: isAuthenticated ? Icons.sync_rounded : Icons.lock_outline_rounded,
            title: isAuthenticated ? '进度已经准备好' : '登录后再打开连续学习',
            subtitle: isAuthenticated ? '下方继续阅读会帮你接回上次停下的位置。' : '登录后可以同步阅读记录、收藏与个人数据。',
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;

        return AppSectionCard(
          padding: EdgeInsets.zero,
          gradient: LinearGradient(
            colors: <Color>[
              AppColors.surface,
              AppColors.brandSoft.withValues(alpha: 0.95),
              const Color(0xFFF8EFE5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: AppColors.borderStrong,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xxl),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: intro),
                      const SizedBox(width: AppSpace.lg),
                      SizedBox(width: 340, child: sidePanel),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      intro,
                      const SizedBox(height: AppSpace.lg),
                      sidePanel,
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAccess(BuildContext context, bool isAuthenticated) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 1040
            ? 3
            : constraints.maxWidth >= 700
                ? 2
                : 1;
        final spacing = AppSpace.md;
        final itemWidth = columnCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (columnCount - 1) * spacing) / columnCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: itemWidth,
              child: _QuickEntryCard(
                icon: Icons.library_books_outlined,
                title: '文章库',
                subtitle: '按分级和阅读节奏挑选今天的文章。',
                actionLabel: '去挑文章',
                onTap: () => context.push('/articles'),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _QuickEntryCard(
                icon: Icons.bookmarks_outlined,
                title: '生词整理',
                subtitle: '把阅读中积累的重点词快速收拢起来。',
                actionLabel: '打开生词本',
                onTap: () => context.push('/vocab'),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _QuickEntryCard(
                icon: isAuthenticated ? Icons.person_outline_rounded : Icons.login_rounded,
                title: isAuthenticated ? '个人中心' : '登录同步',
                subtitle: isAuthenticated ? '查看学习摘要、行为数据和设置入口。' : '登录后同步阅读进度、收藏和学习数据。',
                actionLabel: isAuthenticated ? '查看我的' : '去登录',
                onTap: () => isAuthenticated ? context.push('/me') : context.go('/login'),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(sessionProvider);
    final nickname = session.user?['nickname']?.toString() ?? '学习者';

    return Scaffold(
      appBar: AppBar(title: const Text('首页')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppPageScrollView(
                children: [
                  SizedBox(height: 140),
                  AppLoadingView(label: '正在准备首页内容...'),
                ],
              );
            }
            if (snapshot.hasError) {
              return AppPageScrollView(
                children: [
                  const SizedBox(height: 140),
                  AppErrorState(
                    message: '${snapshot.error}',
                    onRetry: _refresh,
                  ),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final rec = (data['recommendations'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final rawToday = (rec['today'] as List?)?.cast<Map>() ?? const <Map>[];
            final today = rawToday.map((item) => item.cast<String, dynamic>()).toList();
            final rawRecent = (data['recent'] as List?)?.cast<Map>() ?? const <Map>[];
            final recent = rawRecent.map((item) => item.cast<String, dynamic>()).toList();

            return AppPageScrollView(
              maxWidth: AppWidth.wide,
              children: [
                _buildHeroPanel(
                  context,
                  nickname: nickname,
                  isAuthenticated: session.isAuthenticated,
                  today: today,
                  recent: recent,
                ),
                const SizedBox(height: AppSpace.lg),
                _buildQuickAccess(context, session.isAuthenticated),
                const SizedBox(height: AppSpace.xxl),
                _buildSectionHeader(
                  context,
                  title: '今日推荐',
                  subtitle: '像翻开桌边第一本读物一样，从适合今天状态的文章开始。',
                  actionLabel: '查看全部',
                  onAction: () => context.push('/articles'),
                ),
                const SizedBox(height: AppSpace.md),
                if (today.isEmpty)
                  const AppEmptyState(
                    title: '暂时还没有推荐文章',
                    subtitle: '稍后刷新试试，或直接去文章库浏览全部内容。',
                    icon: Icons.menu_book_outlined,
                  )
                else
                  _buildArticleWrap(context, today),
                const SizedBox(height: AppSpace.xxl),
                _buildSectionHeader(
                  context,
                  title: '继续阅读',
                  subtitle: session.isAuthenticated
                      ? '把上次读到一半的内容重新摊开，接着往下读。'
                      : '登录后，系统会自动为你保留阅读节奏与进度。',
                ),
                const SizedBox(height: AppSpace.md),
                if (!session.isAuthenticated)
                  AppEmptyState(
                    title: '登录后可同步继续阅读',
                    subtitle: '系统会记录阅读进度、收藏文章和生词。',
                    icon: Icons.history_outlined,
                    actionLabel: '去登录',
                    onAction: () => context.go('/login'),
                  )
                else if (recent.isEmpty)
                  const AppEmptyState(
                    title: '还没有最近阅读记录',
                    subtitle: '去文章库挑一篇开始读吧。',
                    icon: Icons.chrome_reader_mode_outlined,
                  )
                else
                  _buildArticleWrap(context, recent),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 18, color: AppColors.brandStrong),
          ),
          const SizedBox(width: AppSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeskChecklistItem extends StatelessWidget {
  const _DeskChecklistItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: AppColors.brandStrong),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      onTap: onTap,
      color: AppColors.surface.withValues(alpha: 0.96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: AppColors.brandStrong),
          ),
          const SizedBox(height: AppSpace.md),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpace.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            actionLabel,
            style: theme.textTheme.labelLarge?.copyWith(color: AppColors.brandStrong),
          ),
        ],
      ),
    );
  }
}
