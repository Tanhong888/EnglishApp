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
  late Future<void> _future;
  final Set<int> _updatingWordIds = <int>{};
  final TextEditingController _searchController = TextEditingController();

  static const int _pageSize = 20;
  int _page = 1;
  int _total = 0;
  bool _hasNext = false;
  bool _loadingMore = false;
  String _keyword = '';
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _future = _loadVocab();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVocab({bool loadMore = false}) async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      _items = const <Map<String, dynamic>>[];
      _page = 1;
      _total = 0;
      _hasNext = false;
      return;
    }

    final targetPage = loadMore ? _page + 1 : 1;
    final query = <String, String>{
      'page': targetPage.toString(),
      'size': _pageSize.toString(),
    };
    final trimmedKeyword = _keyword.trim();
    if (trimmedKeyword.isNotEmpty) {
      query['q'] = trimmedKeyword;
    }

    final api = ref.read(authApiProvider);
    final response = await api.get('/me/vocab', query: query, requiresAuth: true);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
    final fetchedItems = rawItems.map((raw) => raw.cast<String, dynamic>()).toList();

    _items = loadMore ? <Map<String, dynamic>>[..._items, ...fetchedItems] : fetchedItems;
    _page = (data['page'] as num?)?.toInt() ?? targetPage;
    _total = (data['total'] as num?)?.toInt() ?? _items.length;
    _hasNext = data['has_next'] as bool? ?? false;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadVocab();
    });
    await _future;
  }

  void _applySearch() {
    final nextKeyword = _searchController.text.trim();
    setState(() {
      _keyword = nextKeyword;
      _future = _loadVocab();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _keyword = '';
      _future = _loadVocab();
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      await _loadVocab(loadMore: true);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载更多失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _setWordMastered(int wordId, bool mastered) async {
    setState(() {
      _updatingWordIds.add(wordId);
    });

    final api = ref.read(authApiProvider);
    try {
      await api.patch(
        '/vocab/word/$wordId',
        requiresAuth: true,
        body: {'mastered': mastered},
      );
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mastered ? '已标记掌握' : '已取消掌握')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingWordIds.remove(wordId);
        });
      }
    }
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
              child: FutureBuilder<void>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done && _items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError && _items.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(child: Text('加载失败：${snapshot.error}')),
                      ],
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _applySearch(),
                        decoration: InputDecoration(
                          hintText: '搜索单词、中文释义或词性',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty || _keyword.isNotEmpty)
                                IconButton(
                                  tooltip: '清空搜索',
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.close),
                                ),
                              IconButton(
                                tooltip: '开始搜索',
                                onPressed: _applySearch,
                                icon: const Icon(Icons.arrow_forward),
                              ),
                            ],
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {});
                        },
                      ),
                      if (_keyword.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '当前搜索：$_keyword',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ..._items.map((item) {
                        final wordId = (item['word_id'] as num?)?.toInt() ?? 0;
                        final latestEntryId = (item['latest_entry_id'] as num?)?.toInt();
                        final mastered = item['mastered'] as bool? ?? false;
                        final updating = _updatingWordIds.contains(wordId);
                        final phonetic = item['phonetic']?.toString();
                        final pos = item['pos']?.toString();
                        final meaning = item['meaning_cn']?.toString() ?? '-';
                        final metaParts = <String>[
                          if (phonetic != null && phonetic.isNotEmpty) '/$phonetic/',
                          if (pos != null && pos.isNotEmpty) pos,
                        ];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: latestEntryId == null ? null : () => context.push('/vocab/$latestEntryId'),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['lemma']?.toString() ?? '-',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: mastered
                                                ? Colors.green.withValues(alpha: 0.12)
                                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(mastered ? '已掌握' : '待复习'),
                                        ),
                                      ],
                                    ),
                                    if (metaParts.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        metaParts.join(' · '),
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(meaning, style: Theme.of(context).textTheme.bodyLarge),
                                    const SizedBox(height: 8),
                                    Text(
                                      '来源记录 ${item['source_count'] ?? 0} 条',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton(
                                          onPressed: latestEntryId == null ? null : () => context.push('/vocab/$latestEntryId'),
                                          child: const Text('查看详情'),
                                        ),
                                        OutlinedButton(
                                          onPressed: updating ? null : () => _setWordMastered(wordId, !mastered),
                                          child: Text(updating ? '更新中...' : (mastered ? '取消掌握' : '标记掌握')),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Center(
                            child: Text(_keyword.isEmpty ? '暂无生词数据' : '没有找到匹配“$_keyword”的生词'),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '已加载 ${_items.length} / $_total 条 · 第 $_page 页 · 每页 $_pageSize 条',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadingMore || !_hasNext ? null : _loadMore,
                                  child: Text(_loadingMore ? '加载中...' : (_hasNext ? '加载更多' : '没有更多了')),
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

