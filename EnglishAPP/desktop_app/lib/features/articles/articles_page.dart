import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../shared/widgets/app_bottom_nav.dart';

class ArticlesPage extends ConsumerStatefulWidget {
  const ArticlesPage({super.key});

  @override
  ConsumerState<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends ConsumerState<ArticlesPage> {
  String _stage = 'all';
  String _sort = 'recommended';
  int _page = 1;
  final int _size = 20;
  late Future<Map<String, dynamic>> _future;
  bool _syncedQueryStage = false;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_syncedQueryStage) {
      return;
    }

    final stage = GoRouterState.of(context).uri.queryParameters['stage'];
    if (stage != null && {'all', 'cet4', 'cet6', 'kaoyan'}.contains(stage)) {
      _stage = stage;
      _page = 1;
      _future = _loadData();
    }
    _syncedQueryStage = true;
  }

  Future<Map<String, dynamic>> _loadData() {
    final api = ref.read(apiClientProvider);
    final query = <String, String>{
      'page': _page.toString(),
      'size': _size.toString(),
      'sort': _sort,
    };
    if (_stage != 'all') {
      query['stage'] = _stage;
    }
    return api.get('/articles', query: query);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  void _reload({bool resetPage = false}) {
    setState(() {
      if (resetPage) {
        _page = 1;
      }
      _future = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      appBar: AppBar(title: const Text('分级阅读')),
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
                  const SizedBox(height: 160),
                  Center(child: Text('加载失败：${snapshot.error}')),
                ],
              );
            }

            final data = ((snapshot.data ?? const <String, dynamic>{})['data'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
            final currentPage = (data['page'] as num?)?.toInt() ?? _page;
            final total = (data['total'] as num?)?.toInt() ?? items.length;
            final hasNext = data['has_next'] as bool? ?? false;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildStageChip('all', '全部'),
                          _buildStageChip('cet4', '四级'),
                          _buildStageChip('cet6', '六级'),
                          _buildStageChip('kaoyan', '考研'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _sort,
                      items: const [
                        DropdownMenuItem(value: 'recommended', child: Text('推荐')),
                        DropdownMenuItem(value: 'latest', child: Text('最新')),
                        DropdownMenuItem(value: 'hot', child: Text('热门')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _sort = value;
                        _reload(resetPage: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...items.map((raw) {
                  final item = raw.cast<String, dynamic>();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(item['title']?.toString() ?? '-'),
                        subtitle: Text(
                          '${item['stage'] ?? '-'} · Level ${item['level'] ?? '-'} · ${item['topic'] ?? '-'}',
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.go('/articles/${item['id']}'),
                      ),
                    ),
                  );
                }),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: Text('暂无符合筛选条件的文章')),
                  ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: currentPage > 1
                                ? () {
                                    _page = currentPage - 1;
                                    _reload();
                                  }
                                : null,
                            child: const Text('上一页'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '第 $currentPage 页 · 每页 $_size 条 · 共 $total 条',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: hasNext
                                ? () {
                                    _page = currentPage + 1;
                                    _reload();
                                  }
                                : null,
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }

  Widget _buildStageChip(String value, String label) {
    final selected = _stage == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        _stage = value;
        _reload(resetPage: true);
      },
    );
  }
}