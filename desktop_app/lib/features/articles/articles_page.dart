import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';
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

  String _stageLabel(String? stage) {
    switch (stage) {
      case 'cet4':
        return 'CET4';
      case 'cet6':
        return 'CET6';
      case 'kaoyan':
        return '考研';
      default:
        return '全部阶段';
    }
  }

  String _sortLabel(String sort) {
    switch (sort) {
      case 'latest':
        return '最新发布';
      case 'hot':
        return '阅读友好';
      default:
        return '推荐排序';
    }
  }

  Widget _buildHero(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppStatusBadge(label: '共享阅读架', tone: AppStatusTone.brand),
        const SizedBox(height: AppSpace.md),
        Text(
          '像翻阅一排分级读本那样挑文章',
          style: AppTheme.kaitiTextStyle(
            theme.textTheme.headlineSmall,
            fontSize: 34,
            height: 1.18,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          '保留原有筛选逻辑，把文章库改成更有桌面感和浏览感的阅读入口。',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpace.lg),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            AppStatusBadge(label: '阶段：${_stageLabel(_stage)}'),
            AppStatusBadge(label: '排序：${_sortLabel(_sort)}'),
            AppStatusBadge(label: '当前展开 ${items.length} 篇', tone: AppStatusTone.warning),
          ],
        ),
      ],
    );

    final notePanel = Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('挑选建议', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpace.md),
          _ShelfTip(
            icon: Icons.flag_outlined,
            title: '先按目标阶段收窄范围',
            subtitle: '用 CET4、CET6 或考研筛出最适合当前备考节奏的内容。',
          ),
          const SizedBox(height: AppSpace.md),
          _ShelfTip(
            icon: Icons.swap_vert_rounded,
            title: '再决定阅读排序',
            subtitle: '可以偏推荐、偏最新，或选择更轻松的阅读友好排序。',
          ),
          const SizedBox(height: AppSpace.md),
          _ShelfTip(
            icon: Icons.chrome_reader_mode_outlined,
            title: '最后点进详情开始读',
            subtitle: '文章详情页和现有路由保持不变，直接承接阅读流程。',
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        return AppSectionCard(
          padding: EdgeInsets.zero,
          gradient: LinearGradient(
            colors: <Color>[
              AppColors.surface,
              const Color(0xFFF8EEE2),
              AppColors.brandSoft.withValues(alpha: 0.94),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: AppColors.borderStrong,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xxl),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: intro),
                      const SizedBox(width: AppSpace.lg),
                      SizedBox(width: 340, child: notePanel),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      intro,
                      const SizedBox(height: AppSpace.lg),
                      notePanel,
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('筛选你的阅读架', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            '保留现有参数，但把选择动作做得更直观一些。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('阶段', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpace.sm),
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
          const SizedBox(height: AppSpace.lg),
          Text('排序', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              ChoiceChip(
                label: const Text('推荐排序'),
                selected: _sort == 'recommended',
                onSelected: (_) => _applySort('recommended'),
              ),
              ChoiceChip(
                label: const Text('最新发布'),
                selected: _sort == 'latest',
                onSelected: (_) => _applySort('latest'),
              ),
              ChoiceChip(
                label: const Text('阅读友好'),
                selected: _sort == 'hot',
                onSelected: (_) => _applySort('hot'),
              ),
            ],
          ),
          if (_stage != null || _sort != 'recommended') ...[
            const SizedBox(height: AppSpace.md),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _stage = null;
                  _sort = 'recommended';
                  _future = _loadArticles();
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('恢复默认浏览方式'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, List<Map<String, dynamic>> items) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('文章列表', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.xs),
        Text(
          '当前展示 ${items.length} 篇文章，点击卡片即可进入原有详情页。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return info;
        }

        return Row(
          children: [
            Expanded(child: info),
            AppStatusBadge(label: _stageLabel(_stage)),
          ],
        );
      },
    );
  }

  Widget _buildArticleShelf(BuildContext context, List<Map<String, dynamic>> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 980 ? 2 : 1;
        final spacing = AppSpace.md;
        final itemWidth = columnCount == 1 ? constraints.maxWidth : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: ArticleSummaryCard(
                  title: item['title']?.toString() ?? '-',
                  badgeLabel: '${_stageLabel(item['stage']?.toString())} · L${item['level'] ?? '-'}',
                  metadata: '主题：${item['topic']} · 预计 ${item['reading_minutes']} 分钟',
                  summary: item['summary']?.toString() ?? '',
                  onTap: ((item['id'] as num?)?.toInt() ?? 0) <= 0
                      ? null
                      : () => context.push('/articles/${(item['id'] as num).toInt()}'),
                ),
              ),
          ],
        );
      },
    );
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
                _buildHero(context, items),
                const SizedBox(height: AppSpace.lg),
                _buildFilters(context),
                const SizedBox(height: AppSpace.xxl),
                _buildSectionHeader(context, items),
                const SizedBox(height: AppSpace.md),
                if (items.isEmpty)
                  const AppEmptyState(
                    title: '没有匹配文章',
                    subtitle: '可以切换分级或排序方式，再试一次。',
                    icon: Icons.search_off_outlined,
                  )
                else
                  _buildArticleShelf(context, items),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}

class _ShelfTip extends StatelessWidget {
  const _ShelfTip({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: AppColors.brandStrong),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
