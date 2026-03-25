import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

class ArticleDetailPage extends ConsumerStatefulWidget {
  const ArticleDetailPage({super.key, required this.articleId});

  final int articleId;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  Future<Map<String, dynamic>>? _future;
  final Map<String, Map<String, dynamic>?> _wordCache = <String, Map<String, dynamic>?>{};
  String? _loadingWord;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    _future = _loadDetail();
  }

  Future<Map<String, dynamic>> _loadDetail() async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    final response = await api.get('/articles/${widget.articleId}');
    final detail = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (session.isAuthenticated) {
      try {
        final status = await api.get('/articles/${widget.articleId}/favorite-status', requiresAuth: true);
        final statusData = (status['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        _favorite = statusData['favorite'] as bool? ?? false;
      } catch (_) {
        _favorite = false;
      }
    }

    return detail;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadDetail();
    });
    await _future;
  }

  Future<void> _toggleFavorite() async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录后可收藏文章')));
      return;
    }

    try {
      if (_favorite) {
        await api.delete('/articles/${widget.articleId}/favorite', requiresAuth: true);
      } else {
        await api.post('/articles/${widget.articleId}/favorite', requiresAuth: true);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _favorite = !_favorite;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('收藏失败：$e')));
    }
  }

  Future<void> _markProgress(int paragraphIndex) async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return;
    }

    try {
      await api.post(
        '/reading/progress',
        requiresAuth: true,
        body: {'article_id': widget.articleId, 'paragraph_index': paragraphIndex},
      );
    } catch (_) {}
  }

  Future<void> _saveWord(Map<String, dynamic>? wordData) async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录后可加入生词本')));
      return;
    }

    final wordId = (wordData?['id'] as num?)?.toInt();
    if (wordId == null) {
      return;
    }

    try {
      await api.post(
        '/vocab',
        requiresAuth: true,
        body: {'word_id': wordId, 'source_article_id': widget.articleId},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入生词本')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入生词本失败：$e')));
    }
  }

  Future<void> _showWordSheet(String word) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }

    Map<String, dynamic>? wordData = _wordCache[normalized];
    if (!_wordCache.containsKey(normalized)) {
      setState(() {
        _loadingWord = normalized;
      });
      try {
        final response = await ref.read(apiClientProvider).get('/words/${Uri.encodeComponent(normalized)}');
        wordData = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        _wordCache[normalized] = wordData;
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          wordData = <String, dynamic>{'lemma': normalized, 'found': false};
          _wordCache[normalized] = wordData;
        } else {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查词失败：${e.message}')));
          return;
        }
      } catch (e) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查词失败：$e')));
        return;
      } finally {
        if (mounted) {
          setState(() {
            _loadingWord = null;
          });
        }
      }
    }

    if (!mounted) {
      return;
    }

    final found = wordData?['found'] as bool?;
    final exists = found != false && wordData != null && wordData.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(normalized, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpace.sm),
              if (!exists)
                Text(
                  '暂未查到这个单词的中文释义，请换一个词再试。',
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else ...[
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    if ((wordData?['phonetic']?.toString() ?? '').isNotEmpty)
                      AppStatusBadge(label: '/${wordData?['phonetic']}/'),
                    if ((wordData?['pos']?.toString() ?? '').isNotEmpty)
                      AppStatusBadge(label: '${wordData?['pos']}'),
                    AppStatusBadge(label: '${wordData?['source'] ?? 'local'}', tone: AppStatusTone.brand),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Text('词元：${wordData?['lemma'] ?? normalized}'),
                const SizedBox(height: AppSpace.xs),
                Text('中文释义：${wordData?['meaning_cn'] ?? '-'}'),
                const SizedBox(height: AppSpace.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _saveWord(wordData),
                    child: const Text('加入生词本'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInteractiveParagraph(String text, int paragraphIndex) {
    final tokens = RegExp(r'[A-Za-z]+|[^A-Za-z]+').allMatches(text).map((m) => m.group(0) ?? '').toList();
    final wordRegex = RegExp(r'^[A-Za-z]+$');

    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: () => _markProgress(paragraphIndex),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Wrap(
            children: tokens.map((token) {
              if (!wordRegex.hasMatch(token)) {
                return Text(token, style: const TextStyle(fontSize: 16, height: 1.8));
              }

              final normalized = token.toLowerCase();
              final cached = _wordCache[normalized];
              final isNotFound = cached != null && ((cached['found'] as bool?) == false);
              final isLoading = _loadingWord == normalized;
              final color = isLoading
                  ? AppColors.warning
                  : (isNotFound ? AppColors.error : AppColors.brandStrong);

              return InkWell(
                onTap: () => _showWordSheet(normalized),
                child: Text(
                  token,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.8,
                    color: color,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: color.withValues(alpha: 0.35),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读详情'),
        actions: [
          IconButton(
            tooltip: _favorite ? '取消收藏' : '收藏文章',
            onPressed: _toggleFavorite,
            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppPageScrollView(
                maxWidth: AppWidth.reading,
                children: [
                  SizedBox(height: 140),
                  AppLoadingView(label: '正在准备文章内容...'),
                ],
              );
            }
            if (snapshot.hasError) {
              return AppPageScrollView(
                maxWidth: AppWidth.reading,
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
            final paragraphs = (data['paragraphs'] as List?)?.cast<Map>() ?? const <Map>[];
            return AppPageScrollView(
              maxWidth: AppWidth.reading,
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
                        Wrap(
                          spacing: AppSpace.xs,
                          runSpacing: AppSpace.xs,
                          children: [
                            AppStatusBadge(label: '${data['stage'] ?? '-'}', tone: AppStatusTone.brand),
                            AppStatusBadge(label: 'L${data['level'] ?? '-'}'),
                            AppStatusBadge(label: '${data['reading_minutes'] ?? '-'} 分钟'),
                            AppStatusBadge(label: '${data['topic'] ?? '-'}'),
                          ],
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text(data['title']?.toString() ?? '-', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          data['summary']?.toString() ?? '进入正文后，点击任意英文单词即可查释义；点击段落可自动记录阅读进度。',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('正文', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    Text(
                      '点击单词查词，点击段落记进度',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                if (paragraphs.isEmpty)
                  const AppEmptyState(
                    title: '这篇文章还没有正文内容',
                    subtitle: '稍后刷新或返回文章库选择其他文章。',
                    icon: Icons.article_outlined,
                  )
                else
                  ...paragraphs.map((raw) {
                    final item = raw.cast<String, dynamic>();
                    final index = (item['index'] as num?)?.toInt() ?? 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.xs),
                            child: Text('段落 $index', style: Theme.of(context).textTheme.labelLarge),
                          ),
                          _buildInteractiveParagraph(item['text']?.toString() ?? '', index),
                        ],
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
