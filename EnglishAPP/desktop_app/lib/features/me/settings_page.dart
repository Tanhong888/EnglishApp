import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

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
      if (!mounted) {
        return;
      }
      setState(() {
        _future = Future.value(data);
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备考目标已更新')));
    } catch (e) {
      if (!mounted) {
        return;
      }
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
    if (!confirmed) {
      return;
    }

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
      // Ignore remote logout failures and always clear the local session.
    } finally {
      await ref.read(sessionProvider.notifier).clear();
    }

    if (!mounted) {
      return;
    }
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
      content: isHardDelete ? '硬删除会立即清除账号与学习数据，且无法恢复。' : '软删除后账号将不可登录，并进入保留期。',
      confirmText: isHardDelete ? '确认硬删除' : '确认软删除',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    final api = ref.read(authApiProvider);
    try {
      await api.delete('/users/me', body: {'mode': mode}, requiresAuth: true);
      await ref.read(sessionProvider.notifier).clear();
      if (!mounted) {
        return;
      }
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isHardDelete ? '账号已硬删除' : '账号已软删除')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('账号删除失败：$e')));
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: session.isAuthenticated
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const AppPageScrollView(
                      children: [
                        SizedBox(height: 140),
                        AppLoadingView(label: '正在加载账号信息...'),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return AppPageScrollView(
                      children: [
                        const SizedBox(height: 140),
                        AppErrorState(
                          message: '${snapshot.error}',
                          onRetry: _refresh,
                        ),
                      ],
                    );
                  }

                  final data = snapshot.data ?? const <String, dynamic>{};
                  final nickname = data['nickname']?.toString() ?? session.user?['nickname']?.toString() ?? '学习者';
                  final email = data['email']?.toString() ?? '-';
                  final target = data['target']?.toString();
                  final isActive = data['is_active'] as bool? ?? true;
                  final deletionDueAt = data['deletion_due_at']?.toString();

                  return AppPageScrollView(
                    maxWidth: AppWidth.content,
                    children: [
                      AppSectionCard(
                        padding: EdgeInsets.zero,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpace.xl),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF9FBFF), Color(0xFFFFFFFF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('账号信息', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: AppSpace.sm),
                              Wrap(
                                spacing: AppSpace.xs,
                                runSpacing: AppSpace.xs,
                                children: [
                                  AppStatusBadge(label: nickname, tone: AppStatusTone.brand),
                                  AppStatusBadge(
                                    label: isActive ? '账号正常' : '账号已停用',
                                    tone: isActive ? AppStatusTone.success : AppStatusTone.warning,
                                  ),
                                  AppStatusBadge(label: _targetLabel(target)),
                                ],
                              ),
                              const SizedBox(height: AppSpace.md),
                              _InfoRow(label: '邮箱', value: email),
                              if (deletionDueAt != null && deletionDueAt.isNotEmpty)
                                _InfoRow(label: '删除截止', value: deletionDueAt),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('切换备考目标', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpace.sm),
                            Wrap(
                              spacing: AppSpace.xs,
                              runSpacing: AppSpace.xs,
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
                      const SizedBox(height: AppSpace.lg),
                      const AppSectionCard(
                        color: AppColors.surfaceMuted,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline),
                          title: Text('当前版本能力'),
                          subtitle: Text('已恢复英语文章阅读、点词查词、文章导入与基础内容运营链路。'),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      AppSectionCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.newspaper_outlined),
                          title: const Text('内容运营'),
                          subtitle: const Text('搜索外部英文文章，导入草稿并发布到阅读库'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => context.push('/admin/content'),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('会话与数据', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpace.md),
                            FilledButton.tonal(
                              onPressed: _submitting ? null : _logout,
                              child: Text(_submitting ? '处理中...' : '退出登录'),
                            ),
                            const SizedBox(height: AppSpace.md),
                            OutlinedButton(
                              onPressed: _submitting ? null : () => _deleteAccount('soft'),
                              child: const Text('软删除账号'),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            OutlinedButton(
                              onPressed: _submitting ? null : () => _deleteAccount('hard'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).colorScheme.error,
                              ),
                              child: const Text('硬删除账号'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          : AppPageScrollView(
              children: [
                const SizedBox(height: 140),
                AppEmptyState(
                  title: '请先登录',
                  subtitle: '登录后才可以查看和管理账号设置。',
                  icon: Icons.lock_outline,
                  actionLabel: '去登录',
                  onAction: () => context.go('/login'),
                ),
              ],
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
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
