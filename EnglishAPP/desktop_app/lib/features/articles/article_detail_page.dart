import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

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
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _wordAudioPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  String? _articleAudioUrl;
  String? _loadedAudioUrl;
  bool _isAudioLoading = false;
  bool _isAudioPlaying = false;
  List<Map<String, dynamic>> _paragraphTimestamps = <Map<String, dynamic>>[];
  int? _currentPlayingParagraphIndex;

  int get _articleId => int.tryParse(widget.articleId) ?? 0;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing;
      final isLoading =
          state.processingState == ProcessingState.loading || state.processingState == ProcessingState.buffering;
      setState(() {
        _isAudioPlaying = playing;
        _isAudioLoading = isLoading;
        if (state.processingState == ProcessingState.completed) {
          _isAudioPlaying = false;
          _currentPlayingParagraphIndex = null;
        }
      });
    });

    _positionSub = _audioPlayer.positionStream.listen((position) {
      if (!mounted || _paragraphTimestamps.isEmpty) {
        return;
      }
      final matchedIndex = _matchParagraphIndexByPosition(position);
      if (matchedIndex != _currentPlayingParagraphIndex) {
        setState(() {
          _currentPlayingParagraphIndex = matchedIndex;
        });
      }
    });

    _future = _loadData();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    unawaited(_audioPlayer.dispose());
    unawaited(_wordAudioPlayer.dispose());
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
    _articleAudioUrl = audioData['article_audio_url']?.toString();
    final ts = (audioData['paragraph_timestamps'] as List?)?.cast<Map>() ?? const <Map>[];
    _paragraphTimestamps = ts
        .map((raw) => raw.cast<String, dynamic>())
        .where((raw) => _durationFromSecond(raw['start']) != null)
        .toList()
      ..sort((a, b) {
        final aStart = _durationFromSecond(a['start']) ?? Duration.zero;
        final bStart = _durationFromSecond(b['start']) ?? Duration.zero;
        return aStart.compareTo(bStart);
      });

    Map<String, dynamic> analyses = <String, dynamic>{'items': <Map<String, dynamic>>[]};
    try {
      final analysesResp = await publicApi.get('/articles/${widget.articleId}/sentence-analyses');
      analyses = (analysesResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    } catch (_) {
      analyses = <String, dynamic>{'items': <Map<String, dynamic>>[]};
    }

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
      'analyses': analyses,
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
  Future<void> _trackEvent(
    String eventName, {
    int? articleId,
    String? word,
    Map<String, dynamic>? contextData,
  }) async {
    final api = ref.read(apiClientProvider);
    final session = ref.read(sessionProvider);

    try {
      await api.post(
        '/analytics/events',
        body: {
          'event_name': eventName,
          'user_id': (session.user?['id'] as num?)?.toInt(),
          'article_id': articleId,
          'word': word,
          'context': contextData,
        },
      );
    } catch (_) {
      // Analytics should never block core user flows.
    }
  }
  Future<void> _playWordPronunciation(String lemma) async {
    final normalized = lemma.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }

    unawaited(_trackEvent('word_pronunciation_tap', articleId: _articleId, word: normalized));
    final publicApi = ref.read(apiClientProvider);
    try {
      final response = await publicApi.get('/words/${Uri.encodeComponent(normalized)}/pronunciation');
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final audioUrl = data['audio_url']?.toString() ?? '';
      if (audioUrl.isEmpty) {
        throw Exception('audio_url_missing');
      }

      await _wordAudioPlayer.stop();
      await _wordAudioPlayer.setUrl(audioUrl);
      await _wordAudioPlayer.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('单词发音失败：$e')));
    }
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
    unawaited(_trackEvent('word_tap', articleId: _articleId, word: lemma));
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
                    onPressed: () => _playWordPronunciation(lemma),
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

  List<Map<String, dynamic>> _matchedAnalyses(
    String paragraphText,
    List<Map<String, dynamic>> analysisItems,
  ) {
    final lowerParagraph = paragraphText.toLowerCase();
    return analysisItems.where((item) {
      final sentence = item['sentence']?.toString().trim().toLowerCase() ?? '';
      return sentence.isNotEmpty && lowerParagraph.contains(sentence);
    }).toList();
  }

  Future<void> _showAnalysisSheet(Map<String, dynamic> analysis) async {
    if (!mounted) return;
    final sentence = analysis['sentence']?.toString() ?? '-';
    final translation = analysis['translation']?.toString() ?? '-';
    final structure = analysis['structure']?.toString() ?? '-';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('重点句解析', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(sentence, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('翻译：$translation'),
              const SizedBox(height: 6),
              Text('结构：$structure'),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
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

  Future<void> _toggleFullAudioPlayback() async {
    if (_audioStatus != 'ready' || _articleAudioUrl == null || _articleAudioUrl!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音频暂不可播放')));
      return;
    }

    if (_isAudioLoading) {
      return;
    }

    setState(() {
      _isAudioLoading = true;
    });

    try {
      if (_loadedAudioUrl != _articleAudioUrl) {
        await _audioPlayer.setUrl(_articleAudioUrl!);
        _loadedAudioUrl = _articleAudioUrl;
      }
      await _audioPlayer.setClip();

      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        setState(() {
          _currentPlayingParagraphIndex = _matchParagraphIndexByPosition(_audioPlayer.position);
        });
        await _audioPlayer.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAudioLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频播放失败：$e')));
    }
  }


  Map<String, dynamic>? _timestampForParagraph(int paragraphIndex) {
    for (final item in _paragraphTimestamps) {
      final idx = (item['index'] as num?)?.toInt() ?? (item['paragraph_index'] as num?)?.toInt();
      if (idx == paragraphIndex) {
        return item;
      }
    }
    return null;
  }

  Duration? _durationFromSecond(dynamic raw) {
    if (raw is int) {
      return Duration(milliseconds: raw * 1000);
    }
    if (raw is double) {
      return Duration(milliseconds: (raw * 1000).round());
    }
    if (raw is num) {
      return Duration(milliseconds: (raw.toDouble() * 1000).round());
    }
    if (raw is String) {
      final value = double.tryParse(raw);
      if (value != null) {
        return Duration(milliseconds: (value * 1000).round());
      }
    }
    return null;
  }

  int? _paragraphIndexFromTimestamp(Map<String, dynamic> item) {
    return (item['index'] as num?)?.toInt() ?? (item['paragraph_index'] as num?)?.toInt();
  }

  int? _matchParagraphIndexByPosition(Duration position) {
    for (final item in _paragraphTimestamps) {
      final start = _durationFromSecond(item['start']);
      if (start == null) {
        continue;
      }
      final end = _durationFromSecond(item['end']);
      final inRange = end == null ? position >= start : position >= start && position < end;
      if (inRange) {
        return _paragraphIndexFromTimestamp(item);
      }
    }
    return null;
  }

  Future<void> _playParagraphAudio(int paragraphIndex) async {
    if (_audioStatus != 'ready' || _articleAudioUrl == null || _articleAudioUrl!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音频暂不可播放')));
      return;
    }
    final ts = _timestampForParagraph(paragraphIndex);
    if (ts == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该段暂无音频时间戳')));
      return;
    }

    final start = _durationFromSecond(ts['start']);
    final end = _durationFromSecond(ts['end']);
    if (start == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该段音频时间戳无效')));
      return;
    }

    setState(() {
      _isAudioLoading = true;
      _currentPlayingParagraphIndex = paragraphIndex;
    });

    try {
      if (_loadedAudioUrl != _articleAudioUrl) {
        await _audioPlayer.setUrl(_articleAudioUrl!);
        _loadedAudioUrl = _articleAudioUrl;
      }
      await _audioPlayer.setClip(start: start, end: end);
      await _audioPlayer.seek(start);
      await _audioPlayer.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAudioLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分段播放失败：$e')));
    }
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
      unawaited(
        _trackEvent(
          'favorite_toggle',
          articleId: _articleId,
          contextData: <String, dynamic>{'favorite': _isFavorited},
        ),
      );
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

          final analysesData = (wrapper['analyses'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          final analysisRawItems = (analysesData['items'] as List?)?.cast<Map>() ?? const <Map>[];
          final analysisItems = analysisRawItems.map((raw) => raw.cast<String, dynamic>()).toList();

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
                const Text('点击蓝色单词可查看释义并加入生词本；黄色段落为重点句'),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...paragraphs.map((raw) {
                          final paragraphMap = raw.cast<String, dynamic>();
                          final paragraphIdx = (paragraphMap['index'] as num?)?.toInt() ?? 1;
                          final text = paragraphMap['text']?.toString() ?? '';
                          if (text.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final matched = _matchedAnalyses(text, analysisItems);
                          final highlighted = matched.isNotEmpty;
                          final hasSegment = _timestampForParagraph(paragraphIdx) != null && _audioStatus == 'ready';
                          final isPlayingParagraph =
                              _currentPlayingParagraphIndex == paragraphIdx && _isAudioPlaying;
                          final showBox = highlighted || isPlayingParagraph;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              width: double.infinity,
                              decoration: showBox
                                  ? BoxDecoration(
                                      color: isPlayingParagraph ? Colors.lightBlue.shade50 : Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isPlayingParagraph ? Colors.lightBlue.shade300 : Colors.amber.shade200,
                                      ),
                                    )
                                  : null,
                              padding: showBox
                                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                                  : EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (highlighted || hasSegment)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        if (highlighted)
                                          TextButton.icon(
                                            onPressed: () => _showAnalysisSheet(matched.first),
                                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                            icon: const Icon(Icons.auto_awesome, size: 16),
                                            label: Text('重点句解析（${matched.length}）'),
                                          ),
                                        if (hasSegment)
                                          OutlinedButton.icon(
                                            onPressed: _isAudioLoading
                                                ? null
                                                : () async {
                                                    if (isPlayingParagraph) {
                                                      await _audioPlayer.pause();
                                                    } else {
                                                      await _playParagraphAudio(paragraphIdx);
                                                    }
                                                  },
                                            icon: Icon(
                                              isPlayingParagraph ? Icons.pause_circle_outline : Icons.play_arrow,
                                              size: 16,
                                            ),
                                            label: Text(isPlayingParagraph ? '暂停本段' : '播放本段'),
                                          ),
                                      ],
                                    ),
                                  _buildInteractiveParagraph(text),
                                ],
                              ),
                            ),
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
                  onPressed: _audioStatus == 'ready' && !_isAudioLoading ? _toggleFullAudioPlayback : null,
                  child: Text(
                    _audioStatus == 'ready'
                        ? (_isAudioLoading ? '加载音频...' : (_isAudioPlaying ? '暂停播放' : '全文播放'))
                        : '音频生成中',
                  ),
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



