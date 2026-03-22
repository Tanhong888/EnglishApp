import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session_controller.dart';

class OnlineArticlesPage extends ConsumerStatefulWidget {
  const OnlineArticlesPage({super.key});

  @override
  ConsumerState<OnlineArticlesPage> createState() => _OnlineArticlesPageState();
}

class _OnlineArticlesPageState extends ConsumerState<OnlineArticlesPage> {
  final TextEditingController _searchController = TextEditingController();
  int _page = 1;
  final int _size = 10;
  String _query = '';
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadResults();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadResults() async {
    final api = ref.read(apiClientProvider);
    final query = <String, String>{
      'page': _page.toString(),
      'size': _size.toString(),
    };
    if (_query.trim().isNotEmpty) {
      query['q'] = _query.trim();
    }

    final response = await api.get('/web-articles/search', query: query);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];

    return {
      'items': items.map((raw) => raw.cast<String, dynamic>()).toList(),
      'page': (data['page'] as num?)?.toInt() ?? _page,
      'size': (data['size'] as num?)?.toInt() ?? _size,
      'total': (data['total'] as num?)?.toInt() ?? 0,
      'has_next': data['has_next'] as bool? ?? false,
      'query': data['query']?.toString() ?? _query,
      'sources_checked': (data['sources_checked'] as num?)?.toInt() ?? 0,
      'source_errors': (data['source_errors'] as List?)?.cast<String>() ?? const <String>[],
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadResults();
    });
    await _future;
  }

  void _search({String? query, int? page}) {
    setState(() {
      if (query != null) {
        _query = query.trim();
        _page = 1;
      }
      if (page != null) {
        _page = page;
      }
      _future = _loadResults();
    });
  }

  String _formatPublishedAt(String? raw) {
    if (raw == null || raw.isEmpty) return '发布时间未知';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('原文链接已复制')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('在线英文文章')),
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
                  const SizedBox(height: 120),
                  Center(child: Text('加载失败：${snapshot.error}')),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            final total = (data['total'] as num?)?.toInt() ?? 0;
            final currentPage = (data['page'] as num?)?.toInt() ?? _page;
            final size = (data['size'] as num?)?.toInt() ?? _size;
            final hasNext = data['has_next'] as bool? ?? false;
            final sourcesChecked = (data['sources_checked'] as num?)?.toInt() ?? 0;
            final sourceErrors = (data['source_errors'] as List?)?.cast<String>() ?? const <String>[];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '自动聚合公开英文新闻源，只展示标题、摘要和原文链接，适合作为后续阅读素材入口。',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '输入关键词，例如 sleep / education / technology',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _search(query: '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) => _search(query: value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => _search(query: _searchController.text),
                      child: const Text('搜索'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: Text(_query.isEmpty ? '最新聚合结果' : '关键词：$_query'),
                    subtitle: Text('已检查 $sourcesChecked 个源 · 当前共 $total 条结果'),
                  ),
                ),
                if (sourceErrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Card(
                      color: const Color(0xFFFFF7E8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('有 ${sourceErrors.length} 个源本次拉取失败，结果仍会展示已成功返回的文章。'),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('暂时没有搜索到结果'),
                      subtitle: Text('可以换一个英文关键词，或者直接先看默认聚合结果。'),
                    ),
                  ),
                ...items.map(
                  (item) {
                    final summary = (item['summary']?.toString() ?? '').trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title']?.toString() ?? '-',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${item['source'] ?? 'Unknown source'} · ${_formatPublishedAt(item['published_at']?.toString())}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 10),
                              Text(summary.isNotEmpty ? summary : '当前源未提供摘要，请复制原文链接查看。'),
                              const SizedBox(height: 12),
                              SelectableText(
                                item['url']?.toString() ?? '-',
                                style: const TextStyle(color: Color(0xFF3554A5)),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: item['url'] == null ? null : () => _copyUrl(item['url'].toString()),
                                  icon: const Icon(Icons.link, size: 18),
                                  label: const Text('复制原文链接'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: currentPage > 1 ? () => _search(page: currentPage - 1) : null,
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
                          onPressed: hasNext ? () => _search(page: currentPage + 1) : null,
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
      ),
    );
  }
}
