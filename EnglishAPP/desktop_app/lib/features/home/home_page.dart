import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final publicApi = ref.read(apiClientProvider);
    final authApi = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);

    final recommendations = await publicApi.get('/home/recommendations');

    var recentItems = <Map<String, dynamic>>[];
    if (session.isAuthenticated) {
      try {
        final recentResponse = await authApi.get('/reading/recent', requiresAuth: true);
        final recentList = (recentResponse['data'] as List?)?.cast<Map>() ?? const <Map>[];
        recentItems = recentList.map((raw) => raw.cast<String, dynamic>()).toList();
      } catch (_) {
        recentItems = <Map<String, dynamic>>[];
      }
    }

    return {
      'recommendations': recommendations,
      'recent_items': recentItems,
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
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
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      appBar: AppBar(title: const Text('首页')),
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
                children: [
                  const SizedBox(height: 160),
                  Center(child: Text('加载失败：${snapshot.error}')),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton(onPressed: _refresh, child: const Text('重试')),
                  ),
                ],
              );
            }

            final wrapper = snapshot.data ?? const <String, dynamic>{};
            final recommendationResponse =
                (wrapper['recommendations'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final recommendationData =
                (recommendationResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final today = (recommendationData['today'] as List?)?.cast<Map>() ?? const <Map>[];
            final quickEntries = (recommendationData['quick_entries'] as List?)?.cast<String>() ?? const <String>[];
            final recentItems = (wrapper['recent_items'] as List?)?.cast<Map<String, dynamic>>() ??
                const <Map<String, dynamic>>[];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('今日推荐', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...today.map((raw) {
                  final item = raw.cast<String, dynamic>();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(item['title']?.toString() ?? '-'),
                        subtitle: Text(
                          '${item['stage'] ?? '-'} · Level ${item['level'] ?? '-'} · ${item['reading_minutes'] ?? '-'} 分钟',
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/articles/${item['id']}'),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Text('最近阅读', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                if (recentItems.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('暂无最近阅读'),
                      subtitle: Text('登录后阅读文章，这里会自动显示'),
                    ),
                  ),
                ...recentItems.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(item['title']?.toString() ?? '-'),
                        subtitle: Text('上次阅读 ${_formatTime(item['last_read_at']?.toString())}'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => context.push('/articles/${item['article_id']}'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('快捷入口', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickEntries
                      .map(
                        (entry) => ActionChip(
                          label: Text(entry.toUpperCase()),
                          onPressed: () => context.go('/articles?stage=$entry'),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(ref.watch(sessionProvider).user?['nickname']?.toString() ?? '学习者'),
                    subtitle: const Text('已连接后端实时数据'),
                    trailing: OutlinedButton(
                      onPressed: () => context.go('/me'),
                      child: const Text('查看我的'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}