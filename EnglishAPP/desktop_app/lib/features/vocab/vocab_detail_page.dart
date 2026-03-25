import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

class VocabDetailPage extends ConsumerStatefulWidget {
  const VocabDetailPage({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<VocabDetailPage> createState() => _VocabDetailPageState();
}

class _VocabDetailPageState extends ConsumerState<VocabDetailPage> {
  late Future<Map<String, dynamic>> _future;
  final Set<int> _updatingSourceIds = <int>{};

  @override
  void initState() {
    super.initState();
    _future = _loadDetail();
  }

  Future<Map<String, dynamic>> _loadDetail() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      return const <String, dynamic>{};
    }

    final api = ref.read(authApiProvider);
    final response = await api.get('/me/vocab/entries/${widget.entryId}', requiresAuth: true);
    return (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadDetail();
    });
    await _future;
  }

  Future<void> _setSourceMastered({
    required int wordId,
    required int sourceArticleId,
    required bool mastered,
  }) async {
    setState(() {
      _updatingSourceIds.add(sourceArticleId);
    });

    final api = ref.read(authApiProvider);
    try {
      await api.patch(
        '/vocab/word/$wordId',
        requiresAuth: true,
        body: {
          'mastered': mastered,
          'source_article_id': sourceArticleId,
        },
      );
      if (!mounted) {
        return;
      }
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mastered ? '已标记该来源为掌握' : '已取消该来源掌握')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingSourceIds.remove(sourceArticleId);
        });
      }
    }
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) {
      return raw;
    }
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('单词详情')),
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
                        AppLoadingView(label: '正在加载单词详情...'),
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
                  final lemma = data['lemma']?.toString() ?? '-';
                  final phonetic = data['phonetic']?.toString();
                  final pos = data['pos']?.toString();
                  final meaning = data['meaning_cn']?.toString() ?? '-';
                  final wordId = (data['word_id'] as num?)?.toInt() ?? 0;
                  final sourceCount = (data['source_count'] as num?)?.toInt() ?? 0;
                  final mastered = data['mastered'] as bool? ?? false;
                  final sources = (data['sources'] as List?)?.cast<Map>() ?? const <Map>[];

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
                              Text(lemma, style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: AppSpace.sm),
                              Wrap(
                                spacing: AppSpace.xs,
                                runSpacing: AppSpace.xs,
                                children: [
                                  if (phonetic != null && phonetic.isNotEmpty) AppStatusBadge(label: '/$phonetic/'),
                                  if (pos != null && pos.isNotEmpty) AppStatusBadge(label: pos),
                                  AppStatusBadge(
                                    label: mastered ? '全部来源已掌握' : '仍有待复习来源',
                                    tone: mastered ? AppStatusTone.success : AppStatusTone.warning,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpace.md),
                              Text(meaning, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                '共关联 $sourceCount 条来源记录',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text('来源明细', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpace.sm),
                      if (sources.isEmpty)
                        const AppEmptyState(
                          title: '暂无来源明细',
                          subtitle: '后续从文章中再次遇到这个单词时，来源记录会显示在这里。',
                          icon: Icons.link_off_outlined,
                        )
                      else
                        ...sources.map((rawSource) {
                          final source = rawSource.cast<String, dynamic>();
                          final sourceArticleId = (source['source_article_id'] as num?)?.toInt() ?? 0;
                          final sourceMastered = source['mastered'] as bool? ?? false;
                          final updating = _updatingSourceIds.contains(sourceArticleId);
                          final sourceTitle = source['source_article_title']?.toString();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.sm),
                            child: AppSectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (sourceTitle == null || sourceTitle.isEmpty)
                                              ? '来源记录 #$sourceArticleId'
                                              : sourceTitle,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpace.sm),
                                      AppStatusBadge(
                                        label: sourceMastered ? '已掌握' : '待复习',
                                        tone: sourceMastered ? AppStatusTone.success : AppStatusTone.neutral,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpace.sm),
                                  Text('来源标识：$sourceArticleId'),
                                  const SizedBox(height: AppSpace.xs),
                                  Text('加入时间：${_formatTime(source['created_at']?.toString())}'),
                                  const SizedBox(height: AppSpace.xs),
                                  Text('最近更新：${_formatTime(source['updated_at']?.toString())}'),
                                  const SizedBox(height: AppSpace.md),
                                  FilledButton.tonal(
                                    onPressed: updating
                                        ? null
                                        : () => _setSourceMastered(
                                              wordId: wordId,
                                              sourceArticleId: sourceArticleId,
                                              mastered: !sourceMastered,
                                            ),
                                    child: Text(updating ? '更新中...' : (sourceMastered ? '取消掌握' : '标记掌握')),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
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
                  subtitle: '登录后才能查看单词详情和来源记录。',
                  icon: Icons.lock_outline,
                  actionLabel: '去登录',
                  onAction: () => context.go('/login'),
                ),
              ],
            ),
    );
  }
}
