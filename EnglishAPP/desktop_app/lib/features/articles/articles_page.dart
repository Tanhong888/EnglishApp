import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

class ArticlesPage extends ConsumerStatefulWidget {
  const ArticlesPage({super.key});

  @override
  ConsumerState<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends ConsumerState<ArticlesPage> {
  Future<List<Map<String, dynamic>>>? _future;
  String? _stage;
  String _sort = 'recommended';

  @override
  void initState() {
    super.initState();
    _future = _loadArticles();
  }

  Future<List<Map<String, dynamic>>> _loadArticles() async {
    final api = ref.read(authApiProvider);
    final query = <String, String>{'page': '1', 'size': '20', 'sort': _sort};
    if (_stage != null && _stage!.isNotEmpty) {
      query['stage'] = _stage!;
    }

    final response = await api.get('/articles', query: query);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
    return rawItems.map((item) => item.cast<String, dynamic>()).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadArticles();
    });
    await _future;
  }

  void _applyStage(String? stage) {
    setState(() {
      _stage = stage;
      _future = _loadArticles();
    });
  }

  void _applySort(String? sort) {
    if (sort == null) return;
    setState(() {
      _sort = sort;
      _future = _loadArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      appBar: AppBar(title: const Text('文章库')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
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

            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _stage == null,
                      onSelected: (_) => _applyStage(null),
                    ),
                    ChoiceChip(
                      label: const Text('CET4'),
                      selected: _stage == 'cet4',
                      onSelected: (_) => _applyStage('cet4'),
                    ),
                    ChoiceChip(
                      label: const Text('CET6'),
                      selected: _stage == 'cet6',
                      onSelected: (_) => _applyStage('cet6'),
                    ),
                    ChoiceChip(
                      label: const Text('考研'),
                      selected: _stage == 'kaoyan',
                      onSelected: (_) => _applyStage('kaoyan'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: '排序方式', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'recommended', child: Text('推荐排序')),
                    DropdownMenuItem(value: 'latest', child: Text('最新发布')),
                    DropdownMenuItem(value: 'hot', child: Text('阅读友好')),
                  ],
                  onChanged: _applySort,
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('没有匹配文章'),
                      subtitle: Text('可以换一个分级或排序方式试试。'),
                    ),
                  )
                else
                  ...items.map((item) {
                    final articleId = (item['id'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => context.push('/articles/$articleId'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(item['title']?.toString() ?? '-', style: Theme.of(context).textTheme.titleMedium),
                                    ),
                                    const SizedBox(width: 12),
                                    Text('${item['stage']} · L${item['level']}'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('主题：${item['topic']} · 预计 ${item['reading_minutes']} 分钟'),
                                const SizedBox(height: 8),
                                Text(
                                  item['summary']?.toString() ?? '',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
