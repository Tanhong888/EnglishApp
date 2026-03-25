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

class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});

  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  Future<Map<String, dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadDashboard();
  }

  Future<Map<String, dynamic>> _loadDashboard() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return {
        'stats': <String, dynamic>{},
        'analytics_summary': <String, dynamic>{},
      };
    }

    final api = ref.read(authApiProvider);
    final statsResp = await api.get('/me/stats', requiresAuth: true);
    final stats = (statsResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    var analyticsSummary = <String, dynamic>{};
    try {
      final summaryResp = await api.get(
        '/analytics/dashboard/me-summary',
        requiresAuth: true,
        query: {'days': '7'},
      );
      analyticsSummary = (summaryResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    } catch (_) {
      analyticsSummary = <String, dynamic>{};
    }

    return {
      'stats': stats,
      'analytics_summary': analyticsSummary,
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadDashboard();
    });
    await _future;
  }

  Widget _buildMetricCard(BuildContext context, String label, String value) {
    return SizedBox(
      width: 220,
      child: AppSectionCard(
        color: AppColors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpace.xs),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(sessionProvider);

    if (!session.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: AppPageScrollView(
          children: [
            const SizedBox(height: 140),
            AppEmptyState(
              title: '登录后查看个人数据',
              subtitle: '包括学习天数、生词统计和近 7 天行为摘要。',
              icon: Icons.person_outline,
              actionLabel: '去登录',
              onAction: () => context.go('/login'),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(location: location),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppPageScrollView(
                children: [
                  SizedBox(height: 140),
                  AppLoadingView(label: '正在加载个人数据...'),
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
            final stats = (data['stats'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final analyticsSummary =
                (data['analytics_summary'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
            final eventCounts =
                (analyticsSummary['event_counts'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

            return AppPageScrollView(
              maxWidth: AppWidth.content,
              children: [
                AppSectionCard(
                  padding: EdgeInsets.zero,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.brandSoft, Color(0xFFFFFFFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppStatusBadge(label: '个人中心', tone: AppStatusTone.brand),
                        const SizedBox(height: AppSpace.md),
                        Text(
                          '你好，${session.user?['nickname'] ?? '学习者'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          '这里汇总你的学习状态、行为指标和常用设置入口。',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    _buildMetricCard(context, '累计学习天数', '${stats['study_days'] ?? 0} 天'),
                    _buildMetricCard(context, '生词收藏', '${stats['vocab_count'] ?? 0} 个'),
                    _buildMetricCard(context, '近 7 天事件', '${analyticsSummary['event_total'] ?? 0} 次'),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                AppSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('近 7 天行为摘要', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: [
                          AppStatusBadge(label: '活跃用户 ${analyticsSummary['dau'] ?? 0}'),
                          AppStatusBadge(label: '点词 ${eventCounts['word_tap'] ?? 0}'),
                          AppStatusBadge(label: '发音 ${eventCounts['word_pronunciation_tap'] ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: AppSpace.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.push('/me/analytics'),
                          child: const Text('查看行为详情'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                AppSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('常用入口', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpace.sm),
                      ListTile(
                        title: const Text('生词本'),
                        subtitle: const Text('查看和管理已收藏单词'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/vocab'),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('设置'),
                        subtitle: const Text('管理账号、会话与基础偏好'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/settings'),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('内容运营'),
                        subtitle: const Text('导入外部文章并发布到阅读库'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/admin/content'),
                      ),
                    ],
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
