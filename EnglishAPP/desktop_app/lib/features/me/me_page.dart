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
  String _learningRange = '30d';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadDashboard();
  }

  Map<String, String>? _learningRecordQuery() {
    switch (_learningRange) {
      case '7d':
        return {'days': '7'};
      case '30d':
        return {'days': '30'};
      case 'all':
        return null;
      default:
        return {'days': '30'};
    }
  }

  Future<Map<String, dynamic>> _loadDashboard() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return {
        'stats': <String, dynamic>{},
        'learning_records': <Map<String, dynamic>>[],
        'recent_reading': <Map<String, dynamic>>[],
        'analytics_summary': <String, dynamic>{},
      };
    }

    final api = ref.read(authApiProvider);
    final statsResp = await api.get('/me/stats', requiresAuth: true);
    final stats = (statsResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    var learningRecords = <Map<String, dynamic>>[];
    try {
      final recordsResp = await api.get(
        '/me/learning-records',
        requiresAuth: true,
        query: _learningRecordQuery(),
      );
      final recordsPayload = recordsResp['data'];
      if (recordsPayload is Map) {
        final recordsData = (recordsPayload['items'] as List?)?.cast<Map>() ?? const <Map>[];
        learningRecords = recordsData.map((raw) => raw.cast<String, dynamic>()).toList();
      } else {
        final recordsData = (recordsPayload as List?)?.cast<Map>() ?? const <Map>[];
        learningRecords = recordsData.map((raw) => raw.cast<String, dynamic>()).toList();
      }
    } catch (_) {
      learningRecords = <Map<String, dynamic>>[];
    }

    var recentReading = <Map<String, dynamic>>[];
    try {
      final recentResp = await api.get('/reading/recent', requiresAuth: true);
      final recentData = (recentResp['data'] as List?)?.cast<Map>() ?? const <Map>[];
      recentReading = recentData.map((raw) => raw.cast<String, dynamic>()).toList();
    } catch (_) {
      recentReading = <Map<String, dynamic>>[];
    }

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
      'learning_records': learningRecords,
      'recent_reading': recentReading,
      'analytics_summary': analyticsSummary,
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadDashboard();
    });
    await _future;
  }

  void _changeLearningRange(String range) {
    if (_learningRange == range) return;
    setState(() {
      _learningRange = range;
      _future = _loadDashboard();
    });
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} $hh:$mm';
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
            child: const Text('去登录后查看学习数据'),
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

            final data = snapshot.data ?? const <String, dynamic>{};
            final stats = (data['stats'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final learningRecords =
                (data['learning_records'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            final recentReading =
                (data['recent_reading'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
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
                        Text('累计阅读 ${stats['read_articles'] ?? 0} 篇'),
                        const SizedBox(height: 6),
                        Text('累计学习 ${stats['study_days'] ?? 0} 天'),
                        const SizedBox(height: 6),
                        Text('生词收藏 ${stats['vocab_count'] ?? 0} 个'),
                        const SizedBox(height: 6),
                        Text('完读率 ${(stats['completion_rate'] ?? 0).toString()}'),
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
                        const SizedBox(height: 6),
                        Text('收藏切换 ${eventCounts['favorite_toggle'] ?? 0} · 小测提交 ${eventCounts['quiz_submit'] ?? 0}'),
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
                const Text('最近学习记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('近7天'),
                      selected: _learningRange == '7d',
                      onSelected: (_) => _changeLearningRange('7d'),
                    ),
                    ChoiceChip(
                      label: const Text('近30天'),
                      selected: _learningRange == '30d',
                      onSelected: (_) => _changeLearningRange('30d'),
                    ),
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _learningRange == 'all',
                      onSelected: (_) => _changeLearningRange('all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (learningRecords.isEmpty)
                  const Card(
                    child: ListTile(title: Text('当前筛选下暂无学习记录')),
                  ),
                ...learningRecords.take(8).map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item['date']?.toString() ?? '-'),
                      subtitle: Text('阅读 ${item['articles'] ?? 0} 篇 · 约 ${item['minutes'] ?? 0} 分钟'),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('查看全部学习记录'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => context.push('/me/learning-records'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('最近阅读', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (recentReading.isEmpty)
                  const Card(
                    child: ListTile(title: Text('暂无最近阅读')),
                  ),
                ...recentReading.take(5).map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item['title']?.toString() ?? '-'),
                      subtitle: Text('上次阅读 ${_formatTime(item['last_read_at']?.toString())}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => context.push('/articles/${item['article_id']}'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('收藏文章'),
                        subtitle: const Text('查看已收藏的阅读内容'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/me/favorites'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('设置'),
                        subtitle: const Text('管理账号、会话与学习数据'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/settings'),
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
