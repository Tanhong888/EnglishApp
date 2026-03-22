import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';

class LearningRecordsPage extends ConsumerStatefulWidget {
  const LearningRecordsPage({super.key});

  @override
  ConsumerState<LearningRecordsPage> createState() => _LearningRecordsPageState();
}

class _LearningRecordsPageState extends ConsumerState<LearningRecordsPage> {
  int _page = 1;
  final int _size = 15;
  String _range = '30d';
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRecords();
  }

  Map<String, String> _query() {
    final query = <String, String>{
      'page': _page.toString(),
      'size': _size.toString(),
    };
    if (_range == '7d') {
      query['days'] = '7';
    } else if (_range == '30d') {
      query['days'] = '30';
    }
    return query;
  }

  Future<Map<String, dynamic>> _loadRecords() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return {
        'items': <Map<String, dynamic>>[],
        'page': _page,
        'size': _size,
        'total': 0,
        'has_next': false,
      };
    }

    final api = ref.read(authApiProvider);
    final response = await api.get('/me/learning-records', requiresAuth: true, query: _query());
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];

    return {
      'items': items.map((raw) => raw.cast<String, dynamic>()).toList(),
      'page': (data['page'] as num?)?.toInt() ?? _page,
      'size': (data['size'] as num?)?.toInt() ?? _size,
      'total': (data['total'] as num?)?.toInt() ?? 0,
      'has_next': data['has_next'] as bool? ?? false,
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadRecords();
    });
    await _future;
  }

  void _reload({int? page, String? range}) {
    setState(() {
      if (page != null) {
        _page = page;
      }
      if (range != null) {
        _range = range;
        _page = 1;
      }
      _future = _loadRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学习记录')),
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
                  final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
                      const <Map<String, dynamic>>[];
                  final currentPage = (data['page'] as num?)?.toInt() ?? _page;
                  final size = (data['size'] as num?)?.toInt() ?? _size;
                  final total = (data['total'] as num?)?.toInt() ?? 0;
                  final hasNext = data['has_next'] as bool? ?? false;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('近7天'),
                            selected: _range == '7d',
                            onSelected: (_) => _reload(range: '7d'),
                          ),
                          ChoiceChip(
                            label: const Text('近30天'),
                            selected: _range == '30d',
                            onSelected: (_) => _reload(range: '30d'),
                          ),
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: _range == 'all',
                            onSelected: (_) => _reload(range: 'all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        const Card(
                          child: ListTile(title: Text('当前筛选下暂无学习记录')),
                        ),
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              title: Text(item['date']?.toString() ?? '-'),
                              subtitle: Text('阅读 ${item['articles'] ?? 0} 篇 · 约 ${item['minutes'] ?? 0} 分钟'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              OutlinedButton(
                                onPressed: currentPage > 1
                                    ? () {
                                        _reload(page: currentPage - 1);
                                      }
                                    : null,
                                child: const Text('上一页'),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '第 $currentPage 页 · 每页 $size 条 · 共 $total 条',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: hasNext
                                    ? () {
                                        _reload(page: currentPage + 1);
                                      }
                                    : null,
                                child: const Text('下一页'),
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
