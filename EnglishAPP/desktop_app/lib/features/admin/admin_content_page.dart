import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/admin_console_controller.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

class AdminContentPage extends ConsumerStatefulWidget {
  const AdminContentPage({super.key});

  @override
  ConsumerState<AdminContentPage> createState() => _AdminContentPageState();
}

class _AdminContentPageState extends ConsumerState<AdminContentPage> {
  final TextEditingController _adminKeyController = TextEditingController(text: 'englishapp-admin-dev');
  final TextEditingController _searchController = TextEditingController();

  bool _searching = false;
  bool _loadingArticles = false;
  bool _savingAdminKey = false;
  final Set<int> _publishingIds = <int>{};
  final Set<String> _importingUrls = <String>{};
  List<Map<String, dynamic>> _searchResults = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _adminArticles = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadAdminArticles();
  }

  @override
  void dispose() {
    _adminKeyController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String> get _adminHeaders => <String, String>{'X-Admin-Key': _adminKeyController.text.trim()};

  Future<void> _persistAdminKey({bool showFeedback = true}) async {
    setState(() {
      _savingAdminKey = true;
    });

    try {
      await ref.read(adminConsoleProvider.notifier).setAdminApiKey(_adminKeyController.text);
      if (!mounted) {
        return;
      }
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('管理密钥已保存')));
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存管理密钥失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingAdminKey = false;
        });
      }
    }
  }

  Future<void> _loadAdminArticles() async {
    setState(() {
      _loadingArticles = true;
    });

    try {
      final response = await ref.read(apiClientProvider).get(
            '/admin/articles',
            query: {'page': '1', 'size': '20'},
            headers: _adminHeaders,
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _adminArticles = rawItems.map((item) => item.cast<String, dynamic>()).toList();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载内容库失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingArticles = false;
        });
      }
    }
  }

  Future<void> _searchWebArticles() async {
    final keyword = _searchController.text.trim();
    setState(() {
      _searching = true;
    });

    try {
      final response = await ref.read(apiClientProvider).get(
            '/web-articles/search',
            query: keyword.isEmpty ? {'page': '1', 'size': '12'} : {'q': keyword, 'page': '1', 'size': '12'},
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = rawItems.map((item) => item.cast<String, dynamic>()).toList();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索外部文章失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _importArticle(Map<String, dynamic> item) async {
    final url = item['url']?.toString() ?? '';
    if (url.isEmpty) {
      return;
    }

    setState(() {
      _importingUrls.add(url);
    });

    try {
      final response = await ref.read(apiClientProvider).post(
            '/web-articles/import',
            headers: _adminHeaders,
            body: {
              'title': item['title'],
              'url': item['url'],
              'source': item['source'],
              'summary': item['summary'],
              'published_at': item['published_at'],
            },
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      await _loadAdminArticles();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((data['idempotent'] as bool? ?? false) ? '已存在同源草稿，直接复用' : '已导入为草稿')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _importingUrls.remove(url);
        });
      }
    }
  }

  Future<void> _publishArticle(int articleId, bool nextPublished) async {
    setState(() {
      _publishingIds.add(articleId);
    });

    try {
      await ref.read(apiClientProvider).post(
            '/admin/articles/$articleId/publish',
            headers: _adminHeaders,
            body: {'is_published': nextPublished},
          );
      await _loadAdminArticles();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextPublished ? '文章已发布' : '文章已转为草稿')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发布操作失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _publishingIds.remove(articleId);
        });
      }
    }
  }

  Future<void> _openEditor({int? articleId}) async {
    await _persistAdminKey(showFeedback: false);
    if (!mounted) {
      return;
    }
    final target = articleId == null ? '/admin/articles/new' : '/admin/articles/$articleId';
    await context.push(target);
    if (!mounted) {
      return;
    }
    await _loadAdminArticles();
  }

  Widget _buildAdminAccessCard(SessionState session) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('运营入口', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            '用于搜索外部英文文章、导入草稿、编辑正文与解析，并发布到阅读库。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _adminKeyController,
            decoration: const InputDecoration(labelText: 'Admin Key'),
            onSubmitted: (_) => _loadAdminArticles(),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton(
                onPressed: _savingAdminKey ? null : _persistAdminKey,
                child: Text(_savingAdminKey ? '保存中...' : '保存管理密钥'),
              ),
              FilledButton.tonalIcon(
                onPressed: _loadingArticles ? null : _loadAdminArticles,
                icon: const Icon(Icons.refresh),
                label: Text(_loadingArticles ? '刷新中...' : '刷新内容库'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('新建文章'),
              ),
              if (session.isAuthenticated)
                OutlinedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('返回阅读首页'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜索外部文章', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchWebArticles(),
            decoration: InputDecoration(
              hintText: '输入关键词，例如 memory / education / AI',
              suffixIcon: IconButton(
                onPressed: _searching ? null : _searchWebArticles,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (_searchResults.isEmpty)
            const AppEmptyState(
              title: '还没有搜索结果',
              subtitle: '可以先尝试搜索一批最新外部文章。',
              icon: Icons.public_outlined,
            )
          else
            ..._searchResults.map((item) {
              final url = item['url']?.toString() ?? '';
              final importing = _importingUrls.contains(url);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppSectionCard(
                  color: AppColors.surfaceMuted,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title']?.toString() ?? '-', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpace.xs),
                      Text('${item['source']} · ${item['published_at'] ?? '-'}'),
                      const SizedBox(height: AppSpace.sm),
                      Text(item['summary']?.toString() ?? ''),
                      const SizedBox(height: AppSpace.md),
                      FilledButton.tonal(
                        onPressed: importing ? null : () => _importArticle(item),
                        child: Text(importing ? '导入中...' : '导入为草稿'),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildLibraryCard() {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本地内容库', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.md),
          if (_adminArticles.isEmpty && !_loadingArticles)
            const AppEmptyState(
              title: '当前还没有内容',
              subtitle: '先从上方导入一篇外部文章试试。',
              icon: Icons.library_books_outlined,
            )
          else
            ..._adminArticles.map((item) {
              final articleId = (item['id'] as num?)?.toInt() ?? 0;
              final isPublished = item['is_published'] as bool? ?? false;
              final publishing = _publishingIds.contains(articleId);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppSectionCard(
                  color: AppColors.surfaceMuted,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(item['title']?.toString() ?? '-', style: Theme.of(context).textTheme.titleMedium),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          AppStatusBadge(
                            label: isPublished ? '已发布' : '草稿',
                            tone: isPublished ? AppStatusTone.success : AppStatusTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text('阶段 ${item['stage']} · L${item['level']} · ${item['topic']} · ${item['paragraph_count']} 段'),
                      if ((item['summary']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          item['summary']?.toString() ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: [
                          FilledButton(
                            onPressed: publishing ? null : () => _publishArticle(articleId, !isPublished),
                            child: Text(publishing ? '处理中...' : (isPublished ? '转为草稿' : '发布到阅读库')),
                          ),
                          OutlinedButton(
                            onPressed: () => _openEditor(articleId: articleId),
                            child: const Text('编辑内容'),
                          ),
                          if (isPublished)
                            OutlinedButton(
                              onPressed: () => context.push('/articles/$articleId'),
                              child: const Text('打开阅读页'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('内容运营')),
      body: AppPageScrollView(
        maxWidth: AppWidth.wide,
        children: [
          _buildAdminAccessCard(session),
          const SizedBox(height: AppSpace.lg),
          _buildSearchCard(),
          const SizedBox(height: AppSpace.lg),
          _buildLibraryCard(),
        ],
      ),
    );
  }
}
