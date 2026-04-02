import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/external_link_opener.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _librarySearchController = TextEditingController();

  bool _searching = false;
  bool _loadingMoreSearchResults = false;
  bool _loadingArticles = false;
  bool _loadingMoreArticles = false;
  final Set<int> _publishingIds = <int>{};
  final Set<String> _importingUrls = <String>{};
  List<Map<String, dynamic>> _searchResults = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _adminArticles = const <Map<String, dynamic>>[];
  int _webSearchPage = 0;
  bool _webSearchHasNext = false;
  int _sourcesChecked = 0;
  List<String> _sourceErrors = const <String>[];
  int _adminArticlesPage = 0;
  bool _adminArticlesHasNext = false;
  bool? _publishedFilter;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    if (session.isAuthenticated && _isAdminSession(session)) {
      _loadAdminArticles();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _librarySearchController.dispose();
    super.dispose();
  }

  bool _isAdminSession(SessionState session) => session.user?['is_admin'] as bool? ?? false;

  String _formatTimestamp(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text;
    }
    final local = parsed.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
  }

  String _hostLabel(String? rawUrl) {
    final url = rawUrl?.trim() ?? '';
    if (url.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return url;
    }
    if (uri.host.isEmpty) {
      return url;
    }
    return uri.host;
  }

  String _sourceTypeLabel(String? type) {
    final normalized = type?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized == 'rss') {
      return 'RSS';
    }
    if (normalized == 'manual') {
      return '手动';
    }
    if (normalized == 'seed') {
      return '种子';
    }
    if (normalized == 'public') {
      return '公共来源';
    }
    return normalized.toUpperCase();
  }

  String _sourceLabel(Map<String, dynamic> item) {
    final source = (item['source'] as Map?)?.cast<String, dynamic>();
    final name = source?['name']?.toString().trim() ?? '';
    final type = _sourceTypeLabel(source?['type']?.toString());
    if (name.isNotEmpty && type.isNotEmpty) {
      return '$name · $type';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (type.isNotEmpty) {
      return type;
    }
    final host = _hostLabel(source?['url']?.toString() ?? item['source_url']?.toString());
    return host.isEmpty ? '来源待补充' : host;
  }

  Future<void> _loadAdminArticles({bool reset = true}) async {
    final nextPage = reset ? 1 : _adminArticlesPage + 1;
    setState(() {
      if (reset) {
        _loadingArticles = true;
      } else {
        _loadingMoreArticles = true;
      }
    });

    try {
      final query = <String, String>{'page': '$nextPage', 'size': '12'};
      final keyword = _librarySearchController.text.trim();
      if (keyword.isNotEmpty) {
        query['q'] = keyword;
      }
      if (_publishedFilter != null) {
        query['published'] = _publishedFilter! ? 'true' : 'false';
      }

      final response = await ref.read(authApiProvider).get(
            '/admin/articles',
            query: query,
            requiresAuth: true,
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
      final items = rawItems.map((item) => item.cast<String, dynamic>()).toList();
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _adminArticles = items;
        } else {
          final merged = <Map<String, dynamic>>[..._adminArticles];
          final existingIds = merged.map((item) => (item['id'] as num?)?.toInt()).toSet();
          for (final item in items) {
            final articleId = (item['id'] as num?)?.toInt();
            if (!existingIds.contains(articleId)) {
              merged.add(item);
            }
          }
          _adminArticles = merged;
        }
        _adminArticlesPage = (data['page'] as num?)?.toInt() ?? nextPage;
        _adminArticlesHasNext = data['has_next'] as bool? ?? false;
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
          _loadingMoreArticles = false;
        });
      }
    }
  }

  Future<void> _searchWebArticles({bool reset = true}) async {
    final keyword = _searchController.text.trim();
    final nextPage = reset ? 1 : _webSearchPage + 1;
    setState(() {
      if (reset) {
        _searching = true;
      } else {
        _loadingMoreSearchResults = true;
      }
    });

    try {
      final query = <String, String>{'page': '$nextPage', 'size': '12'};
      if (keyword.isNotEmpty) {
        query['q'] = keyword;
      }
      final response = await ref.read(apiClientProvider).get('/web-articles/search', query: query);
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
      final items = rawItems.map((item) => item.cast<String, dynamic>()).toList();
      final sourceErrors = ((data['source_errors'] as List?) ?? const <dynamic>[]).map((item) => item.toString()).toList();
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _searchResults = items;
        } else {
          final merged = <Map<String, dynamic>>[..._searchResults];
          final existingUrls = merged.map((item) => item['url']?.toString()).toSet();
          for (final item in items) {
            final url = item['url']?.toString();
            if (!existingUrls.contains(url)) {
              merged.add(item);
            }
          }
          _searchResults = merged;
        }
        _webSearchPage = (data['page'] as num?)?.toInt() ?? nextPage;
        _webSearchHasNext = data['has_next'] as bool? ?? false;
        _sourcesChecked = (data['sources_checked'] as num?)?.toInt() ?? 0;
        _sourceErrors = sourceErrors;
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
          _loadingMoreSearchResults = false;
        });
      }
    }
  }

  Future<void> _openSourceUrl(String url) async {
    final opened = await openExternalUrl(url);
    if (!mounted) {
      return;
    }
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开原文链接')));
    }
  }

  Future<void> _importArticle(
    Map<String, dynamic> item, {
    bool openEditorAfter = false,
  }) async {
    final url = item['url']?.toString() ?? '';
    if (url.isEmpty) {
      return;
    }

    setState(() {
      _importingUrls.add(url);
    });

    try {
      final response = await ref.read(authApiProvider).post(
            '/web-articles/import',
            requiresAuth: true,
            body: {
              'title': item['title'],
              'url': item['url'],
              'source': item['source'],
              'summary': item['summary'],
              'published_at': item['published_at'],
            },
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final articleId = (data['article_id'] as num?)?.toInt() ?? 0;
      await _loadAdminArticles(reset: true);
      if (!mounted) {
        return;
      }
      final idempotent = data['idempotent'] as bool? ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(idempotent ? '已复用已有草稿' : '已导入为草稿')),
      );
      if (openEditorAfter && articleId > 0) {
        await context.push('/admin/articles/$articleId');
        if (!mounted) {
          return;
        }
        await _loadAdminArticles(reset: true);
      }
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
      await ref.read(authApiProvider).post(
            '/admin/articles/$articleId/publish',
            requiresAuth: true,
            body: {'is_published': nextPublished},
          );
      await _loadAdminArticles(reset: true);
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
    final target = articleId == null ? '/admin/articles/new' : '/admin/articles/$articleId';
    await context.push(target);
    if (!mounted) {
      return;
    }
    await _loadAdminArticles(reset: true);
  }

  void _applyPublishedFilter(bool? value) {
    setState(() {
      _publishedFilter = value;
    });
    _loadAdminArticles(reset: true);
  }

  Widget _buildAdminAccessCard(SessionState session) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('运营入口', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            '后台权限现在跟随登录账号。当前页面用于搜索外部英文文章、导入草稿、编辑正文与解析，并发布到阅读库。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: _loadingArticles ? null : () => _loadAdminArticles(reset: true),
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

  Widget _buildSearchResultCard(Map<String, dynamic> item) {
    final url = item['url']?.toString() ?? '';
    final importing = _importingUrls.contains(url);
    final publishedAt = _formatTimestamp(item['published_at']);
    final source = item['source']?.toString() ?? 'Unknown Source';
    final summary = item['summary']?.toString() ?? '';
    final host = _hostLabel(url);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppSectionCard(
        color: AppColors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['title']?.toString() ?? '-', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                AppStatusBadge(label: source, tone: AppStatusTone.brand),
                AppStatusBadge(label: publishedAt),
                if (host.isNotEmpty) AppStatusBadge(label: host),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: url.isEmpty ? null : () => _openSourceUrl(url),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('查看原文'),
                ),
                FilledButton.tonal(
                  onPressed: importing ? null : () => _importArticle(item),
                  child: Text(importing ? '导入中...' : '导入为草稿'),
                ),
                FilledButton(
                  onPressed: importing ? null : () => _importArticle(item, openEditorAfter: true),
                  child: Text(importing ? '处理中...' : '导入并编辑'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜索外部文章', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            '支持从 RSS/Atom 源拉取文章列表，先导入草稿，再补正文和解析后发布。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchWebArticles(reset: true),
            decoration: InputDecoration(
              hintText: '输入关键词，例如 memory / education / AI',
              suffixIcon: IconButton(
                onPressed: _searching ? null : () => _searchWebArticles(reset: true),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (_sourcesChecked > 0) ...[
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                AppStatusBadge(label: '已检查 $_sourcesChecked 个源', tone: AppStatusTone.brand),
                AppStatusBadge(
                  label: _sourceErrors.isEmpty ? '源状态正常' : '失败 ${_sourceErrors.length} 个源',
                  tone: _sourceErrors.isEmpty ? AppStatusTone.success : AppStatusTone.warning,
                ),
              ],
            ),
            if (_sourceErrors.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '失败源：${_sourceErrors.join('；')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: AppSpace.md),
          ],
          if (_searching && _searchResults.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: AppLoadingView(label: '正在搜索外部文章...'),
            )
          else if (_searchResults.isEmpty)
            const AppEmptyState(
              title: '还没有搜索结果',
              subtitle: '可以先尝试搜索一批最新外部文章。',
              icon: Icons.public_outlined,
            )
          else ...[
            ..._searchResults.map(_buildSearchResultCard),
            if (_webSearchHasNext)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _loadingMoreSearchResults ? null : () => _searchWebArticles(reset: false),
                  icon: const Icon(Icons.expand_more),
                  label: Text(_loadingMoreSearchResults ? '加载中...' : '加载更多结果'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLibraryArticleCard(Map<String, dynamic> item) {
    final articleId = (item['id'] as num?)?.toInt() ?? 0;
    final isPublished = item['is_published'] as bool? ?? false;
    final publishing = _publishingIds.contains(articleId);
    final summary = item['summary']?.toString() ?? '';
    final sourceLabel = _sourceLabel(item);
    final sourceUrl = item['source_url']?.toString() ?? '';

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
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                AppStatusBadge(label: '阶段 ${item['stage']} · L${item['level']}', tone: AppStatusTone.brand),
                AppStatusBadge(label: item['topic']?.toString() ?? 'topic'),
                AppStatusBadge(label: '${item['paragraph_count']} 段'),
                AppStatusBadge(label: sourceLabel),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text('更新于 ${_formatTimestamp(item['updated_at'])}'),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                summary,
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
                if (sourceUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _openSourceUrl(sourceUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('原文来源'),
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
  }

  Widget _buildLibraryCard() {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本地内容库', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            '这里集中管理草稿和已发布文章，支持按状态筛选，并继续编辑导入内容。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _librarySearchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadAdminArticles(reset: true),
            decoration: InputDecoration(
              hintText: '按标题、摘要或来源搜索草稿',
              suffixIcon: IconButton(
                onPressed: _loadingArticles ? null : () => _loadAdminArticles(reset: true),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: _publishedFilter == null,
                onSelected: (_) => _applyPublishedFilter(null),
              ),
              ChoiceChip(
                label: const Text('仅草稿'),
                selected: _publishedFilter == false,
                onSelected: (_) => _applyPublishedFilter(false),
              ),
              ChoiceChip(
                label: const Text('仅已发布'),
                selected: _publishedFilter == true,
                onSelected: (_) => _applyPublishedFilter(true),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (_loadingArticles && _adminArticles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: AppLoadingView(label: '正在加载内容库...'),
            )
          else if (_adminArticles.isEmpty)
            const AppEmptyState(
              title: '当前还没有内容',
              subtitle: '先从上方导入一篇外部文章试试。',
              icon: Icons.library_books_outlined,
            )
          else ...[
            ..._adminArticles.map(_buildLibraryArticleCard),
            if (_adminArticlesHasNext)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _loadingMoreArticles ? null : () => _loadAdminArticles(reset: false),
                  icon: const Icon(Icons.expand_more),
                  label: Text(_loadingMoreArticles ? '加载中...' : '加载更多文章'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isAdmin = _isAdminSession(session);

    return Scaffold(
      appBar: AppBar(title: const Text('内容运营')),
      body: !session.isAuthenticated
          ? AppPageScrollView(
              children: [
                const SizedBox(height: 140),
                AppEmptyState(
                  title: '请先登录',
                  subtitle: '登录管理员账号后才可以进入内容运营后台。',
                  icon: Icons.lock_outline,
                  actionLabel: '去登录',
                  onAction: () => context.go('/login'),
                ),
              ],
            )
          : !isAdmin
              ? const AppPageScrollView(
                  children: [
                    SizedBox(height: 140),
                    AppEmptyState(
                      title: '当前账号没有后台权限',
                      subtitle: '请使用管理员账号登录后再进入内容运营页。',
                      icon: Icons.admin_panel_settings_outlined,
                    ),
                  ],
                )
              : AppPageScrollView(
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

