import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  int _page = 1;
  final int _size = 10;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadFavorites();
  }

  Future<Map<String, dynamic>> _loadFavorites() async {
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
    final response = await api.get(
      '/me/favorites',
      requiresAuth: true,
      query: {
        'page': _page.toString(),
        'size': _size.toString(),
      },
    );
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
      _future = _loadFavorites();
    });
    await _future;
  }

  void _goToPage(int page) {
    if (page < 1) return;
    setState(() {
      _page = page;
      _future = _loadFavorites();
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
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏文章')),
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

                  if (items.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 140),
                        const Center(child: Text('还没有收藏文章')),
                        if (currentPage > 1)
                          Center(
                            child: OutlinedButton(
                              onPressed: () => _goToPage(1),
                              child: const Text('返回第一页'),
                            ),
                          ),
                      ],
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              title: Text(item['title']?.toString() ?? '-'),
                              subtitle: Text('收藏于 ${_formatTime(item['favorited_at']?.toString())}'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => context.push('/articles/${item['article_id']}'),
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
                                onPressed: currentPage > 1 ? () => _goToPage(currentPage - 1) : null,
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
                                onPressed: hasNext ? () => _goToPage(currentPage + 1) : null,
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