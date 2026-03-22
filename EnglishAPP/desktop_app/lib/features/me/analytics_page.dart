import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';

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
      padding: const EdgeInsets.only(bottom: 6),
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
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(child: Text('加载失败：${snapshot.error}')),
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

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
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
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('统计窗口：近 $windowDays 天', style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text('事件总数：$eventTotal'),
                              const SizedBox(height: 6),
                              Text('活跃用户：$dau'),
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
                              const Text('关键事件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              _metricLine('点词', eventCounts['word_tap']),
                              _metricLine('发音点击', eventCounts['word_pronunciation_tap']),
                              _metricLine('收藏切换', eventCounts['favorite_toggle']),
                              _metricLine('小测提交', eventCounts['quiz_submit']),
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
                              const Text('高频点击单词', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              if (topWords.isEmpty) const Text('暂无单词点击数据'),
                              ...topWords.take(8).map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text('${item['word'] ?? '-'} · ${item['count'] ?? 0} 次'),
                                ),
                              ),
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
                              const Text('事件趋势', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              if (timeline.isEmpty) const Text('暂无趋势数据'),
                              ...timeline.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text('${item['date'] ?? '-'}：${item['events'] ?? 0} 次事件'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          : Center(
              child: FilledButton(
                onPressed: () => context.go('/login'),
                child: const Text('请先登录'),
              ),
            ),
    );
  }
}

