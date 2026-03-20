import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

class VocabPage extends ConsumerStatefulWidget {
  const VocabPage({super.key});

  @override
  ConsumerState<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends ConsumerState<VocabPage> {
  int? _sourceArticleId;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadVocab();
  }

  Future<List<Map<String, dynamic>>> _loadVocab() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) return const <Map<String, dynamic>>[];

    final query = <String, String>{'page': '1', 'size': '20'};
    if (_sourceArticleId != null) {
      query['source_article_id'] = _sourceArticleId.toString();
    }

    final api = ref.read(apiClientProvider);
    final response = await api.get('/me/vocab', accessToken: session.accessToken, query: query);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
    return items.map((raw) => raw.cast<String, dynamic>()).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadVocab();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('生词本')),
      body: session.isAuthenticated
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
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

                  final items = snapshot.data ?? const <Map<String, dynamic>>[];
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('全部来源'),
                            selected: _sourceArticleId == null,
                            onSelected: (_) {
                              setState(() {
                                _sourceArticleId = null;
                                _future = _loadVocab();
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('文章 #1'),
                            selected: _sourceArticleId == 1,
                            onSelected: (_) {
                              setState(() {
                                _sourceArticleId = 1;
                                _future = _loadVocab();
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('文章 #2'),
                            selected: _sourceArticleId == 2,
                            onSelected: (_) {
                              setState(() {
                                _sourceArticleId = 2;
                                _future = _loadVocab();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              title: Text(item['lemma']?.toString() ?? '-'),
                              subtitle: Text(
                                '来源 ${item['source_count'] ?? 0} 篇 · 最新文章 #${item['latest_source_article_id'] ?? '-'}',
                              ),
                              trailing: Text((item['mastered'] as bool? ?? false) ? '已掌握' : '未掌握'),
                            ),
                          ),
                        ),
                      ),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Center(child: Text('暂无生词数据')),
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
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
