import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});

  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  Future<Map<String, dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadStats();
  }

  Future<Map<String, dynamic>> _loadStats() {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return Future.value({'data': <String, dynamic>{}});
    }
    final api = ref.read(authApiProvider);
    return api.get('/me/stats', requiresAuth: true);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadStats();
    });
    await _future;
  }

  Future<void> _deleteAccount(String mode) async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) return;

    final api = ref.read(authApiProvider);
    try {
      await api.delete('/users/me', body: {'mode': mode}, requiresAuth: true);
      await ref.read(sessionProvider.notifier).clear();
      if (!mounted) return;
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('账号已${mode == 'soft' ? '软删除' : '硬删除'}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('账号删除失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(sessionProvider);

    if (!session.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('去登录后查看学习数据'),
          ),
        ),
        bottomNavigationBar: AppBottomNav(location: location),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = ((snapshot.data ?? const <String, dynamic>{})['data'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('你好，${session.user?['nickname'] ?? '学习者'}', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        Text('累计阅读 ${data['read_articles'] ?? 0} 篇'),
                        const SizedBox(height: 6),
                        Text('累计学习 ${data['study_days'] ?? 0} 天'),
                        const SizedBox(height: 6),
                        Text('生词收藏 ${data['vocab_count'] ?? 0} 个'),
                        const SizedBox(height: 6),
                        Text('完读率 ${(data['completion_rate'] ?? 0).toString()}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: const Text('收藏文章'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => context.go('/me/favorites'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await ref.read(sessionProvider.notifier).clear();
                          if (!context.mounted) return;
                          context.go('/login');
                        },
                        child: const Text('退出本地会话'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _deleteAccount('soft'),
                        child: const Text('软删除账号'),
                      ),
                    ),
                  ],
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

