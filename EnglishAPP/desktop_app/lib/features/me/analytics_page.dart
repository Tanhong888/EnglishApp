import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

class MeAnalyticsPage extends ConsumerStatefulWidget {
  const MeAnalyticsPage({super.key});

  @override
  ConsumerState<MeAnalyticsPage> createState() => _MeAnalyticsPageState();
}

class _MeAnalyticsPageState extends ConsumerState<MeAnalyticsPage> {
  int _days = 7;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadSummary();
  }

  Future<Map<String, dynamic>> _loadSummary() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return {
        'window_days': _days,
        'event_total': 0,
        'dau': 0,
        'event_counts': <String, dynamic>{},
        'timeline': <Map<String, dynamic>>[],
        'top_words': <Map<String, dynamic>>[],
      };
    }

    final api = ref.read(authApiProvider);
    final response = await api.get(
      '/analytics/dashboard/me-summary',
      requiresAuth: true,
      query: {'days': _days.toString()},
    );
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return {
      'window_days': (data['window_days'] as num?)?.toInt() ?? _days,
      'event_total': (data['event_total'] as num?)?.toInt() ?? 0,
      'dau': (data['dau'] as num?)?.toInt() ?? 0,
      'event_counts': (data['event_counts'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      'timeline': ((data['timeline'] as List?)?.cast<Map>() ?? const <Map>[])
          .map((raw) => raw.cast<String, dynamic>())
          .toList(),
      'top_words': ((data['top_words'] as List?)?.cast<Map>() ?? const <Map>[])
          .map((raw) => raw.cast<String, dynamic>())
          .toList(),
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSummary();
    });
    await _future;
  }

  void _changeDays(int days) {
    if (_days == days) {
      return;
    }
    setState(() {
      _days = days;
      _future = _loadSummary();
    });
  }

  Widget _metricLine(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('${value ?? 0}'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('行为指标')),
      body: session.isAuthenticated
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const AppPageScrollView(
                      children: [
                        SizedBox(height: 140),
                        AppLoadingView(label: '正在加载行为指标...'),
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
                  final windowDays = (data['window_days'] as num?)?.toInt() ?? _days;
                  final eventTotal = (data['event_total'] as num?)?.toInt() ?? 0;
                  final dau = (data['dau'] as num?)?.toInt() ?? 0;
                  final eventCounts =
                      (data['event_counts'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
                  final timeline =
                      (data['timeline'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
                  final topWords =
                      (data['top_words'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];

                  return AppPageScrollView(
                    maxWidth: AppWidth.content,
                    children: [
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('查看近期学习行为变化', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpace.md),
                            Wrap(
                              spacing: AppSpace.xs,
                              runSpacing: AppSpace.xs,
                              children: [
                                ChoiceChip(
                                  label: const Text('近7天'),
                                  selected: _days == 7,
                                  onSelected: (_) => _changeDays(7),
                                ),
                                ChoiceChip(
                                  label: const Text('近30天'),
                                  selected: _days == 30,
                                  onSelected: (_) => _changeDays(30),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.sm,
                        children: [
                          SizedBox(
                            width: 220,
                            child: AppSectionCard(
                              color: AppColors.surfaceMuted,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('统计窗口'),
                                  const SizedBox(height: AppSpace.xs),
                                  Text('近 $windowDays 天', style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: AppSectionCard(
                              color: AppColors.surfaceMuted,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('事件总数'),
                                  const SizedBox(height: AppSpace.xs),
                                  Text('$eventTotal', style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: AppSectionCard(
                              color: AppColors.surfaceMuted,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('活跃用户'),
                                  const SizedBox(height: AppSpace.xs),
                                  Text('$dau', style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.lg),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('关键事件', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpace.md),
                            _metricLine('点词', eventCounts['word_tap']),
                            _metricLine('发音点击', eventCounts['word_pronunciation_tap']),
                            _metricLine('收藏切换', eventCounts['favorite_toggle']),
                            _metricLine('小测提交', eventCounts['quiz_submit']),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('高频点击单词', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpace.md),
                            if (topWords.isEmpty)
                              const AppEmptyState(
                                title: '暂无单词点击数据',
                                subtitle: '后续在阅读中多点词，这里会显示高频单词。',
                                icon: Icons.touch_app_outlined,
                              )
                            else
                              Wrap(
                                spacing: AppSpace.xs,
                                runSpacing: AppSpace.xs,
                                children: topWords.take(8).map(
                                  (item) {
                                    final word = item['word']?.toString() ?? '-';
                                    final count = item['count'] ?? 0;
                                    return AppStatusBadge(
                                      label: '$word · $count 次',
                                      tone: AppStatusTone.brand,
                                    );
                                  },
                                ).toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('事件趋势', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpace.md),
                            if (timeline.isEmpty)
                              const AppEmptyState(
                                title: '暂无趋势数据',
                                subtitle: '当前窗口内还没有足够的趋势样本。',
                                icon: Icons.show_chart_outlined,
                              )
                            else
                              ...timeline.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text('${item['date'] ?? '-'}')),
                                      Text('${item['events'] ?? 0} 次事件'),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          : AppPageScrollView(
              children: [
                const SizedBox(height: 140),
                AppEmptyState(
                  title: '请先登录',
                  subtitle: '登录后才可以查看行为指标。',
                  icon: Icons.lock_outline,
                  actionLabel: '去登录',
                  onAction: () => context.go('/login'),
                ),
              ],
            ),
    );
  }
}
