import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';

class ArticleDetailPage extends ConsumerStatefulWidget {
  const ArticleDetailPage({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool _isFavorited = false;
  bool _favoriteSubmitting = false;
  bool _progressSubmitting = false;
  bool _addingVocab = false;
  String _audioStatus = 'pending';
  final TextEditingController _wordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final publicApi = ref.read(apiClientProvider);
    final authApi = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);

    final detail = await publicApi.get('/articles/${widget.articleId}');
    final audio = await publicApi.get('/articles/${widget.articleId}/audio');
    final audioData = (audio['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    _audioStatus = audioData['status']?.toString() ?? 'pending';

    if (session.isAuthenticated) {
      try {
        final favoriteStatus = await authApi.get(
          '/articles/${widget.articleId}/favorite-status',
          requiresAuth: true,
        );
        final favoriteData = (favoriteStatus['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        _isFavorited = favoriteData['favorite'] as bool? ?? false;
      } catch (_) {
        _isFavorited = false;
      }
    } else {
      _isFavorited = false;
    }

    return {
      'detail': detail,
      'audio': audio,
    };
  }

  List<String> _extractTopWords(List<Map> paragraphs) {
    final stopWords = <String>{
      'the',
      'and',
      'that',
      'with',
      'this',
      'from',
      'have',
      'will',
      'your',
      'you',
      'for',
      'are',
      'was',
      'were',
      'but',
      'not',
      'can',
      'into',
      'than',
      'then',
      'they',
      'them',
      'their',
      'also',
      'about',
      'while',
      'after',
      'before',
      'because',
      'which',
      'where',
      'when',
    };

    final counts = <String, int>{};
    final regex = RegExp(r"[A-Za-z]+", caseSensitive: false);

    for (final raw in paragraphs) {
      final text = raw.cast<String, dynamic>()['text']?.toString() ?? '';
      for (final match in regex.allMatches(text)) {
        final word = match.group(0)?.toLowerCase() ?? '';
        if (word.length < 4 || stopWords.contains(word)) {
          continue;
        }
        counts[word] = (counts[word] ?? 0) + 1;
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) {
          return byCount;
        }
        return a.key.compareTo(b.key);
      });

    return entries.take(12).map((e) => e.key).toList();
  }

  Future<void> _toggleFavorite() async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录再收藏')));
      return;
    }

    setState(() {
      _favoriteSubmitting = true;
    });

    final authApi = ref.read(authApiProvider);
    try {
      if (_isFavorited) {
        await authApi.delete('/articles/${widget.articleId}/favorite', requiresAuth: true);
      } else {
        await authApi.post('/articles/${widget.articleId}/favorite', requiresAuth: true);
      }
      if (!mounted) return;
      setState(() {
        _isFavorited = !_isFavorited;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('收藏操作失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _favoriteSubmitting = false;
        });
      }
    }
  }

  Future<void> _saveProgress(int paragraphIndex) async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录再保存进度')));
      return;
    }

    setState(() {
      _progressSubmitting = true;
    });

    final authApi = ref.read(authApiProvider);
    try {
      await authApi.post(
        '/reading/progress',
        requiresAuth: true,
        body: {
          'article_id': int.tryParse(widget.articleId) ?? 0,
          'paragraph_index': paragraphIndex,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('阅读进度已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存进度失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _progressSubmitting = false;
        });
      }
    }
  }

  Future<void> _lookupAndAddVocab([String? presetWord]) async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录再加入生词本')));
      return;
    }

    final rawWord = (presetWord ?? _wordController.text).trim().toLowerCase();
    if (rawWord.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入要查询的单词')));
      return;
    }

    setState(() {
      _addingVocab = true;
    });

    final publicApi = ref.read(apiClientProvider);
    final authApi = ref.read(authApiProvider);
    try {
      final wordResp = await publicApi.get('/words/${Uri.encodeComponent(rawWord)}');
      final wordData = (wordResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final wordId = (wordData['id'] as num?)?.toInt();
      if (wordId == null) {
        throw Exception('word_id_missing');
      }

      final addResp = await authApi.post(
        '/vocab',
        requiresAuth: true,
        body: {
          'word_id': wordId,
          'source_article_id': int.tryParse(widget.articleId) ?? 0,
        },
      );
      final addData = (addResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final created = addData['created'] as bool? ?? false;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(created ? '已加入生词本：$rawWord' : '生词已存在该文章来源：$rawWord')),
      );
      _wordController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查词或加入失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _addingVocab = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读详情')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }

          final wrapper = snapshot.data ?? const <String, dynamic>{};
          final detailResponse = (wrapper['detail'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          final detailData = (detailResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

          final audioResponse = (wrapper['audio'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          final audioData = (audioResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          final paragraphs = (detailData['paragraphs'] as List?)?.cast<Map>() ?? const <Map>[];
          final audioStatus = audioData['status']?.toString() ?? 'pending';
          _audioStatus = audioStatus;
          final paragraphIndex = paragraphs.isEmpty ? 1 : paragraphs.length;
          final quickWords = _extractTopWords(paragraphs);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        detailData['title']?.toString() ?? '-',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: _favoriteSubmitting ? null : _toggleFavorite,
                      icon: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${detailData['stage'] ?? '-'} · Level ${detailData['level'] ?? '-'} · ${detailData['reading_minutes'] ?? '-'} 分钟',
                ),
                const SizedBox(height: 8),
                Text('音频状态：$audioStatus'),
                if (audioStatus == 'failed')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('音频生成失败，请稍后重试或使用文本阅读。'),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      paragraphs
                          .map((raw) => raw.cast<String, dynamic>()['text']?.toString() ?? '')
                          .where((line) => line.isNotEmpty)
                          .join('\n\n'),
                      style: const TextStyle(height: 1.7, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _progressSubmitting ? null : () => _saveProgress(paragraphIndex),
                        child: Text(_progressSubmitting ? '保存中...' : '保存阅读进度'),
                      ),
                    ),
                  ],
                ),
                if (quickWords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('快捷点词加入生词本'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickWords
                        .map(
                          (word) => ActionChip(
                            label: Text(word),
                            onPressed: _addingVocab ? null : () => _lookupAndAddVocab(word),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wordController,
                        decoration: const InputDecoration(
                          hintText: '输入单词（如 consolidate）',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addingVocab ? null : _lookupAndAddVocab,
                      child: Text(_addingVocab ? '处理中...' : '查词并加入生词本'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_audioStatus != 'failed')
                OutlinedButton(
                  onPressed: _audioStatus == 'ready'
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Windows 端全文播放即将接入')),
                          );
                        }
                      : null,
                  child: Text(_audioStatus == 'ready' ? '全文播放' : '音频生成中'),
                ),
              OutlinedButton(
                onPressed: () => context.go('/articles/${widget.articleId}/analysis'),
                child: const Text('句子解析'),
              ),
              FilledButton(
                onPressed: () => context.go('/articles/${widget.articleId}/quiz'),
                child: const Text('开始小测'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
