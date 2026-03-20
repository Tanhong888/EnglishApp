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
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadFavorites();
  }

  Future<List<Map<String, dynamic>>> _loadFavorites() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) return const <Map<String, dynamic>>[];

    final api = ref.read(authApiProvider);
    final response = await api.get('/me/favorites', requiresAuth: true);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
    return items.map((raw) => raw.cast<String, dynamic>()).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadFavorites();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏文章')),
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
                  if (items.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 160),
                        Center(child: Text('还没有收藏文章')),
                      ],
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        child: ListTile(
                          title: Text(item['title']?.toString() ?? '-'),
                          subtitle: Text('收藏于 ${item['favorited_at'] ?? '-'}'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => context.go('/articles/${item['article_id']}'),
                        ),
                      );
                    },
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

