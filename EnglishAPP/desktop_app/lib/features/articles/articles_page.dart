import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/article_summary_card.dart';

class ArticlesPage extends ConsumerStatefulWidget {
  const ArticlesPage({super.key});

  @override
  ConsumerState<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends ConsumerState<ArticlesPage> {
  Future<List<Map<String, dynamic>>>? _future;
  String? _stage;
  String _sort = 'recommended';

  @override
  void initState() {
    super.initState();
    _future = _loadArticles();
  }

  Future<List<Map<String, dynamic>>> _loadArticles() async {
    final api = ref.read(authApiProvider);
    final query = <String, String>{'page': '1', 'size': '20', 'sort': _sort};
    if (_stage != null && _stage!.isNotEmpty) {
      query['stage'] = _stage!;
    }

    final response = await api.get('/articles', query: query);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
    return rawItems.map((item) => item.cast<String, dynamic>()).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadArticles();
    });
    await _future;
  }

  void _applyStage(String? stage) {
    setState(() {
      _stage = stage;
      _future = _loadArticles();
    });
  }

  void _applySort(String? sort) {
    if (sort == null) {
      return;
    }
    setState(() {
      _sort = sort;
      _future = _loadArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      appBar: AppBar(title: const Text('文章库')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppPageScrollView(
                children: [
                  SizedBox(height: 140),
                  AppLoadingView(label: '正在加载文章列表...'),
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

            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            return AppPageScrollView(
              maxWidth: AppWidth.wide,
              children: [
                AppSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('按阶段筛选适合自己的文章', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        '保留简洁筛选逻辑，先按考试目标找范围，再决定排序方式。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: [
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: _stage == null,
                            onSelected: (_) => _applyStage(null),
                          ),
                          ChoiceChip(
                            label: const Text('CET4'),
                            selected: _stage == 'cet4',
                            onSelected: (_) => _applyStage('cet4'),
                          ),
                          ChoiceChip(
                            label: const Text('CET6'),
                            selected: _stage == 'cet6',
                            onSelected: (_) => _applyStage('cet6'),
                          ),
                          ChoiceChip(
                            label: const Text('考研'),
                            selected: _stage == 'kaoyan',
                            onSelected: (_) => _applyStage('kaoyan'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.md),
                      DropdownButtonFormField<String>(
                        initialValue: _sort,
                        decoration: const InputDecoration(labelText: '排序方式'),
                        items: const [
                          DropdownMenuItem(value: 'recommended', child: Text('推荐排序')),
                          DropdownMenuItem(value: 'latest', child: Text('最新发布')),
                          DropdownMenuItem(value: 'hot', child: Text('阅读友好')),
                        ],
                        onChanged: _applySort,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                if (items.isEmpty)
                  const AppEmptyState(
                    title: '没有匹配文章',
                    subtitle: '可以切换分级或排序方式，再试一次。',
                    icon: Icons.search_off_outlined,
                  )
                else
                  ...items.map((item) {
                    final articleId = (item['id'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: ArticleSummaryCard(
                        title: item['title']?.toString() ?? '-',
                        badgeLabel: '${item['stage']} · L${item['level']}',
                        metadata: '主题：${item['topic']} · 预计 ${item['reading_minutes']} 分钟',
                        summary: item['summary']?.toString() ?? '',
                        onTap: articleId <= 0 ? null : () => context.push('/articles/$articleId'),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
