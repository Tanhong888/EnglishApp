import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

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

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(sessionProvider);

    if (!session.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('去登录'),
          ),
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
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 140),
                  Center(child: Text('加载失败：${snapshot.error}')),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final stats = (data['stats'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final analyticsSummary =
                (data['analytics_summary'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
            final eventCounts =
                (analyticsSummary['event_counts'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('你好，${session.user?['nickname'] ?? '学习者'}', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        Text('累计学习 ${stats['study_days'] ?? 0} 天'),
                        const SizedBox(height: 6),
                        Text('生词收藏 ${stats['vocab_count'] ?? 0} 个'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('近7天行为指标', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('事件总数 ${analyticsSummary['event_total'] ?? 0}'),
                        const SizedBox(height: 6),
                        Text('活跃用户 ${analyticsSummary['dau'] ?? 0}'),
                        const SizedBox(height: 6),
                        Text('点词 ${eventCounts['word_tap'] ?? 0} · 发音 ${eventCounts['word_pronunciation_tap'] ?? 0}'),
                        const SizedBox(height: 4),
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
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('生词本'),
                        subtitle: const Text('查看和管理已收藏单词'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/vocab'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('设置'),
                        subtitle: const Text('管理账号、会话与基础偏好'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/settings'),
                      ),
                      const Divider(height: 1),
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

