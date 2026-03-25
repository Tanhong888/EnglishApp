import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session_controller.dart';

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
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mastered ? '已标记该来源为掌握' : '已取消该来源掌握')),
      );
    } catch (e) {
      if (!mounted) return;
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
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
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
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 140),
                        Center(child: Text('加载失败：${snapshot.error}')),
                        const SizedBox(height: 12),
                        Center(
                          child: OutlinedButton(
                            onPressed: _refresh,
                            child: const Text('重试'),
                          ),
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

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(lemma, style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (phonetic != null && phonetic.isNotEmpty) _MetaChip(label: '/$phonetic/'),
                                  if (pos != null && pos.isNotEmpty) _MetaChip(label: pos),
                                  _MetaChip(label: mastered ? '全部来源已掌握' : '仍有待复习来源'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(meaning, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
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
                      const SizedBox(height: 12),
                      Text('来源明细', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...sources.map((rawSource) {
                        final source = rawSource.cast<String, dynamic>();
                        final sourceArticleId = (source['source_article_id'] as num?)?.toInt() ?? 0;
                        final sourceMastered = source['mastered'] as bool? ?? false;
                        final updating = _updatingSourceIds.contains(sourceArticleId);
                        final sourceTitle = source['source_article_title']?.toString();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
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
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: sourceMastered
                                              ? Colors.green.withValues(alpha: 0.12)
                                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(sourceMastered ? '已掌握' : '待复习'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('来源标识：$sourceArticleId'),
                                  const SizedBox(height: 4),
                                  Text('加入时间：${_formatTime(source['created_at']?.toString())}'),
                                  const SizedBox(height: 4),
                                  Text('最近更新：${_formatTime(source['updated_at']?.toString())}'),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
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
                          ),
                        );
                      }),
                      if (sources.isEmpty)
                        const Card(
                          child: ListTile(title: Text('暂无来源明细')),
                        ),
                    ],
                  );
                },
              ),
            )
          : const Center(child: Text('请先登录')),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

