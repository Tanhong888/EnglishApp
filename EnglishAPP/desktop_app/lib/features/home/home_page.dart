import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
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
    BuildContext context,
    String title, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
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
            final today = (rec['today'] as List?)?.cast<Map>() ?? const <Map>[];
            final recent = (data['recent'] as List?)?.cast<Map>() ?? const <Map>[];

            return AppPageScrollView(
              maxWidth: AppWidth.wide,
              children: [
                AppSectionCard(
                  padding: EdgeInsets.zero,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.brandSoft, Color(0xFFFDFEFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppStatusBadge(
                          label: session.isAuthenticated ? '已登录同步' : '访客模式',
                          tone: session.isAuthenticated ? AppStatusTone.brand : AppStatusTone.neutral,
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text('你好，$nickname', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          '从一篇合适的文章开始，阅读时可以直接点词查看释义，并把重点单词保存到生词本。',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: AppSpace.lg),
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.sm,
                          children: [
                            FilledButton.icon(
                              onPressed: () => context.push('/articles'),
                              icon: const Icon(Icons.auto_stories_outlined),
                              label: const Text('浏览文章库'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/vocab'),
                              icon: const Icon(Icons.bookmark_outline),
                              label: const Text('打开生词本'),
                            ),
                            if (!session.isAuthenticated)
                              OutlinedButton.icon(
                                onPressed: () => context.go('/login'),
                                icon: const Icon(Icons.login),
                                label: const Text('登录同步进度'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                _buildSectionHeader(
                  context,
                  '今日推荐',
                  actionLabel: '查看全部',
                  onAction: () => context.push('/articles'),
                ),
                const SizedBox(height: AppSpace.sm),
                if (today.isEmpty)
                  const AppEmptyState(
                    title: '暂时还没有推荐文章',
                    subtitle: '稍后刷新试试，或直接去文章库浏览全部内容。',
                    icon: Icons.menu_book_outlined,
                  )
                else
                  ...today.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _buildArticleCard(context, item.cast<String, dynamic>()),
                    ),
                  ),
                const SizedBox(height: AppSpace.lg),
                _buildSectionHeader(context, '继续阅读'),
                const SizedBox(height: AppSpace.sm),
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
                  ...recent.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _buildArticleCard(context, item.cast<String, dynamic>()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
