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
  final Set<String> _addedWords = <String>{};

  int get _articleId => int.tryParse(widget.articleId) ?? 0;

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

  Future<Map<String, dynamic>> _lookupWordDetail(String word) async {
    final publicApi = ref.read(apiClientProvider);
    final response = await publicApi.get('/words/${Uri.encodeComponent(word.trim().toLowerCase())}');
    return (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<bool> _addWordToVocab({
    required int wordId,
    required String lemma,
    bool showSnack = true,
  }) async {
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) {
      if (mounted && showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录再加入生词本')));
      }
      return false;
    }

    final authApi = ref.read(authApiProvider);
    try {
      final addResp = await authApi.post(
        '/vocab',
        requiresAuth: true,
        body: {
          'word_id': wordId,
          'source_article_id': _articleId,
        },
      );
      final addData = (addResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final created = addData['created'] as bool? ?? false;

      if (mounted) {
        setState(() {
          _addedWords.add(lemma.toLowerCase());
        });
      }

      if (mounted && showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(created ? '已加入生词本：$lemma' : '生词已存在该文章来源：$lemma')),
        );
      }
      return true;
    } catch (e) {
      if (mounted && showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入生词本失败：$e')));
      }
      return false;
    }
  }

  Future<void> _openWordCard(String word) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }

    Map<String, dynamic> wordData;
    try {
      wordData = await _lookupWordDetail(normalized);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查词失败：$e')));
      return;
    }

    if (!mounted) return;

    final lemma = wordData['lemma']?.toString() ?? normalized;
    final phonetic = wordData['phonetic']?.toString() ?? '-';
    final pos = wordData['pos']?.toString() ?? '-';
    final meaning = wordData['meaning_cn']?.toString() ?? '-';
    final wordId = (wordData['id'] as num?)?.toInt();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var alreadyAdded = _addedWords.contains(lemma.toLowerCase());
        var submitting = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lemma, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('音标：$phonetic'),
                  const SizedBox(height: 6),
                  Text('词性：$pos'),
                  const SizedBox(height: 6),
                  Text('释义：$meaning'),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('单词发音能力即将接入 Windows 端')),
                      );
                    },
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('发音'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('关闭'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: (wordId == null || alreadyAdded || submitting)
                            ? null
                            : () async {
                                setSheetState(() {
                                  submitting = true;
                                });
                                final ok = await _addWordToVocab(
                                  wordId: wordId,
                                  lemma: lemma,
                                  showSnack: true,
                                );
                                if (!mounted) return;
                                setSheetState(() {
                                  submitting = false;
                                  if (ok) {
                                    alreadyAdded = true;
                                  }
                                });
                              },
                        child: Text(
                          submitting
                              ? '加入中...'
                              : (alreadyAdded ? '已在生词本' : '加入生词本'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInteractiveParagraph(String text) {
    final tokenRegex = RegExp(r"[A-Za-z]+|[^A-Za-z]+");
    final wordRegex = RegExp(r"^[A-Za-z]+$");
    final tokens = tokenRegex.allMatches(text).map((m) => m.group(0) ?? '').toList();

    return Wrap(
      children: tokens.map((token) {
        if (wordRegex.hasMatch(token)) {
          final normalized = token.toLowerCase();
          final isAdded = _addedWords.contains(normalized);
          return InkWell(
            onTap: () => _openWordCard(normalized),
            child: Text(
              token,
              style: TextStyle(
                fontSize: 16,
                height: 1.7,
                color: isAdded ? Colors.green.shade700 : Colors.blue.shade700,
                decoration: TextDecoration.underline,
              ),
            ),
          );
        }

        return Text(
          token,
          style: const TextStyle(height: 1.7, fontSize: 16),
        );
      }).toList(),
    );
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
          'article_id': _articleId,
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
    final rawWord = (presetWord ?? _wordController.text).trim().toLowerCase();
    if (rawWord.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入要查询的单词')));
      return;
    }

    setState(() {
      _addingVocab = true;
    });

    try {
      final wordData = await _lookupWordDetail(rawWord);
      final wordId = (wordData['id'] as num?)?.toInt();
      final lemma = wordData['lemma']?.toString() ?? rawWord;
      if (wordId == null) {
        throw Exception('word_id_missing');
      }

      await _addWordToVocab(wordId: wordId, lemma: lemma, showSnack: true);
      if (mounted) {
        _wordController.clear();
      }
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
                const SizedBox(height: 8),
                const Text('点击蓝色单词可查看释义并加入生词本'),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...paragraphs.map((raw) {
                          final text = raw.cast<String, dynamic>()['text']?.toString() ?? '';
                          if (text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildInteractiveParagraph(text),
                          );
                        }),
                      ],
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