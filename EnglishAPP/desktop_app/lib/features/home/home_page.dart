import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHome();
  }

  Future<Map<String, dynamic>> _loadHome() async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    final recommendations = await api.get('/home/recommendations');
    var recentItems = <Map<String, dynamic>>[];

    if (session.isAuthenticated) {
      try {
        final recent = await api.get('/reading/recent', requiresAuth: true);
        final rawRecent = (recent['data'] as List?)?.cast<Map>() ?? const <Map>[];
        recentItems = rawRecent.map((item) => item.cast<String, dynamic>()).toList();
      } catch (_) {
        recentItems = <Map<String, dynamic>>[];
      }
    }

    return {
      'recommendations': (recommendations['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      'recent': recentItems,
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadHome();
    });
    await _future;
  }

  Widget _buildArticleCard(BuildContext context, Map<String, dynamic> item) {
    final articleId = (item['id'] as num?)?.toInt() ?? (item['article_id'] as num?)?.toInt() ?? 0;
    final title = item['title']?.toString() ?? 'Untitled';
    final stage = item['stage']?.toString() ?? '-';
    final topic = item['topic']?.toString() ?? '-';
    final minutes = item['reading_minutes']?.toString() ?? '-';
    final summary = item['summary']?.toString();
    final progress = (item['progress_percent'] as num?)?.toDouble();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: articleId <= 0 ? null : () => context.push('/articles/$articleId'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$stage · ${minutes}min'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('主题：$topic'),
              if (summary != null && summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: (progress / 100).clamp(0, 1)),
                const SizedBox(height: 6),
                Text('继续阅读进度 ${progress.toStringAsFixed(0)}%'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(sessionProvider);
    final nickname = session.user?['nickname']?.toString() ?? '学习者';

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
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 140),
                  Center(child: Text('加载失败：${snapshot.error}')),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final rec = (data['recommendations'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            final today = (rec['today'] as List?)?.cast<Map>() ?? const <Map>[];
            final recent = (data['recent'] as List?)?.cast<Map>() ?? const <Map>[];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('你好，$nickname', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 10),
                        const Text('这里是英语阅读主场景。先选文章开始阅读，进入详情后可以直接点击任意英文单词查释义、音标和词性。'),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: () => context.push('/articles'),
                              child: const Text('浏览文章库'),
                            ),
                            OutlinedButton(
                              onPressed: () => context.push('/vocab'),
                              child: const Text('打开生词本'),
                            ),
                            if (!session.isAuthenticated)
                              OutlinedButton(
                                onPressed: () => context.go('/login'),
                                child: const Text('登录同步进度'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('今日推荐', style: Theme.of(context).textTheme.titleLarge)),
                    TextButton(
                      onPressed: () => context.push('/articles'),
                      child: const Text('查看全部'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (today.isEmpty)
                  const Card(child: ListTile(title: Text('暂时还没有推荐文章')))
                else
                  ...today.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildArticleCard(context, item.cast<String, dynamic>()),
                      )),
                const SizedBox(height: 8),
                Text('继续阅读', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (!session.isAuthenticated)
                  const Card(
                    child: ListTile(
                      title: Text('登录后可同步继续阅读'),
                      subtitle: Text('系统会记录你的阅读进度、收藏文章和生词。'),
                    ),
                  )
                else if (recent.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('还没有最近阅读记录'),
                      subtitle: Text('去文章库挑一篇开始读吧。'),
                    ),
                  )
                else
                  ...recent.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildArticleCard(context, item.cast<String, dynamic>()),
                      )),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
