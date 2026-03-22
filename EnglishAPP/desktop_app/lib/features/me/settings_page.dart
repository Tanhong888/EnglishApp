import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_preferences_controller.dart';
import '../../core/state/session_controller.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late Future<Map<String, dynamic>> _future;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return const <String, dynamic>{};
    }

    final api = ref.read(authApiProvider);
    final response = await api.get('/users/me', requiresAuth: true);
    return (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadProfile();
    });
    await _future;
  }

  String _targetLabel(String? target) {
    switch (target) {
      case 'cet4':
        return '四级备考';
      case 'cet6':
        return '六级备考';
      case 'kaoyan':
        return '考研英语';
      default:
        return '未设置';
    }
  }

  String _readingFontLabel(String value) {
    switch (value) {
      case 'small':
        return '小';
      case 'large':
        return '大';
      default:
        return '中';
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmText,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _updateTarget(String target) async {
    setState(() {
      _submitting = true;
    });

    final api = ref.read(authApiProvider);
    try {
      final response = await api.patch('/users/me', requiresAuth: true, body: {'target': target});
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      await ref.read(sessionProvider.notifier).updateUser({'target': data['target'] ?? target});
      if (!mounted) return;
      setState(() {
        _future = Future.value(data);
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备考目标已更新')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新备考目标失败：$e')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: '退出登录',
      content: '退出后会清除本地登录状态，需要重新输入账号密码。',
      confirmText: '确认退出',
    );
    if (!confirmed) return;

    setState(() {
      _submitting = true;
    });

    final session = ref.read(sessionProvider);
    final api = ref.read(apiClientProvider);

    try {
      final refreshToken = session.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await api.post('/auth/logout', body: {'refresh_token': refreshToken});
      }
    } catch (_) {
      // Even if the remote logout fails, local session should still be cleared.
    } finally {
      await ref.read(sessionProvider.notifier).clear();
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
    });
    context.go('/login');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  Future<void> _deleteAccount(String mode) async {
    final isHardDelete = mode == 'hard';
    final confirmed = await _confirm(
      title: isHardDelete ? '硬删除账号' : '软删除账号',
      content: isHardDelete
          ? '硬删除会立即清除账号与学习数据，且无法恢复。'
          : '软删除后账号将不可登录，并进入保留期。',
      confirmText: isHardDelete ? '确认硬删除' : '确认软删除',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() {
      _submitting = true;
    });

    final api = ref.read(authApiProvider);
    try {
      await api.delete('/users/me', body: {'mode': mode}, requiresAuth: true);
      await ref.read(sessionProvider.notifier).clear();
      if (!mounted) return;
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isHardDelete ? '账号已硬删除' : '账号已软删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('账号删除失败：$e')));
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final preferences = ref.watch(appPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
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
                  final nickname = data['nickname']?.toString() ?? session.user?['nickname']?.toString() ?? '学习者';
                  final email = data['email']?.toString() ?? '-';
                  final target = data['target']?.toString();
                  final isActive = data['is_active'] as bool? ?? true;
                  final deletionDueAt = data['deletion_due_at']?.toString();

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '账号信息',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              _InfoRow(label: '昵称', value: nickname),
                              _InfoRow(label: '邮箱', value: email),
                              _InfoRow(label: '当前目标', value: _targetLabel(target)),
                              _InfoRow(label: '账号状态', value: isActive ? '正常' : '已停用'),
                              if (deletionDueAt != null && deletionDueAt.isNotEmpty)
                                _InfoRow(label: '删除截止', value: deletionDueAt),
                              const SizedBox(height: 8),
                              Text(
                                '切换备考目标',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('四级'),
                                    selected: target == 'cet4',
                                    onSelected: _submitting ? null : (_) => _updateTarget('cet4'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('六级'),
                                    selected: target == 'cet6',
                                    onSelected: _submitting ? null : (_) => _updateTarget('cet6'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('考研'),
                                    selected: target == 'kaoyan',
                                    onSelected: _submitting ? null : (_) => _updateTarget('kaoyan'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '阅读与朗读偏好',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '阅读字号',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('小'),
                                    selected: preferences.readingFontSize == 'small',
                                    onSelected: (_) => ref.read(appPreferencesProvider.notifier).setReadingFontSize('small'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('中'),
                                    selected: preferences.readingFontSize == 'medium',
                                    onSelected: (_) => ref.read(appPreferencesProvider.notifier).setReadingFontSize('medium'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('大'),
                                    selected: preferences.readingFontSize == 'large',
                                    onSelected: (_) => ref.read(appPreferencesProvider.notifier).setReadingFontSize('large'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '当前字号：${_readingFontLabel(preferences.readingFontSize)}，会立刻应用到阅读详情正文。',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('点词后自动发音'),
                                subtitle: const Text('打开单词释义卡时自动播放发音，关闭后需手动点击发音按钮。'),
                                value: preferences.autoPlayWordAudio,
                                onChanged: (value) =>
                                    ref.read(appPreferencesProvider.notifier).setAutoPlayWordAudio(value),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.favorite_border),
                              title: const Text('收藏文章'),
                              subtitle: const Text('查看已收藏的阅读内容'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => context.push('/me/favorites'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.history),
                              title: const Text('学习记录'),
                              subtitle: const Text('查看按日期聚合的学习轨迹'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => context.push('/me/learning-records'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '会话与数据',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: _submitting ? null : _logout,
                                child: Text(_submitting ? '处理中...' : '退出登录'),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _submitting ? null : () => _deleteAccount('soft'),
                                child: const Text('软删除账号'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _submitting ? null : () => _deleteAccount('hard'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                child: const Text('硬删除账号'),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Windows V1 先提供基础账号与数据管理，后续可继续扩展更多个性化偏好。',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
