import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../core/network/api_client.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

enum _ReadingMode { english, bilingual, translated }

class ArticleDetailPage extends ConsumerStatefulWidget {
  const ArticleDetailPage({super.key, required this.articleId});

  final int articleId;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  Future<Map<String, dynamic>>? _future;
  late final AudioPlayer _audioPlayer;
  final Map<String, Map<String, dynamic>?> _wordCache = <String, Map<String, dynamic>?>{};
  final Map<int, int> _quizSelections = <int, int>{};
  String? _loadingWord;
  String? _loadedAudioUrl;
  String? _audioError;
  bool _favorite = false;
  bool _audioLoading = false;
  bool _submittingQuiz = false;
  _ReadingMode _readingMode = _ReadingMode.english;
  Map<String, dynamic>? _quizResult;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _future = _loadDetail();
  }

  Future<Map<String, dynamic>> _loadDetail() async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    final response = await api.get('/articles/${widget.articleId}');
    final detail = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final analysesResponse = await api.get('/articles/${widget.articleId}/sentence-analyses');
    final quizResponse = await api.get('/articles/${widget.articleId}/quiz');
    final analysesData = (analysesResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final quizData = (quizResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    Map<String, dynamic> audioData = <String, dynamic>{
      'status': detail['audio_status']?.toString() ?? 'pending',
      'article_audio_url': null,
      'paragraph_timestamps': const <dynamic>[],
      'retry_hint': null,
    };

    try {
      final audioResponse = await api.get('/articles/${widget.articleId}/audio');
      final responseData = (audioResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      audioData = <String, dynamic>{...audioData, ...responseData};
    } catch (_) {}

    detail['sentence_analyses'] = ((analysesData['items'] as List?)?.cast<Map>() ?? const <Map>[])
        .map((item) => item.cast<String, dynamic>())
        .toList();
    detail['quiz_questions'] = ((quizData['questions'] as List?)?.cast<Map>() ?? const <Map>[])
        .map((item) => item.cast<String, dynamic>())
        .toList();
    detail['audio'] = audioData;

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
    await _audioPlayer.stop();
    setState(() {
      _loadedAudioUrl = null;
      _audioError = null;
      _quizSelections.clear();
      _quizResult = null;
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

  Future<void> _toggleAudioPlayback(String url) async {
    setState(() {
      _audioLoading = true;
      _audioError = null;
    });

    try {
      if (_loadedAudioUrl != url) {
        await _audioPlayer.stop();
        await _audioPlayer.setUrl(url);
        _loadedAudioUrl = url;
      }

      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.seek(Duration.zero);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioError = '音频播放失败，请稍后重试。';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频播放失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _audioLoading = false;
        });
      }
    }
  }

  Future<void> _restartAudio() async {
    try {
      await _audioPlayer.seek(Duration.zero);
      if (!_audioPlayer.playing) {
        await _audioPlayer.play();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioError = '音频重播失败，请稍后重试。';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频重播失败：$e')));
    }
  }

  Future<void> _seekAudio(double value, Duration duration) async {
    final clampedMilliseconds = value.clamp(0, duration.inMilliseconds.toDouble()).round();
    await _audioPlayer.seek(Duration(milliseconds: clampedMilliseconds));
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

  void _selectQuizOption(int questionId, int optionIndex) {
    setState(() {
      _quizSelections[questionId] = optionIndex;
    });
  }

  Future<void> _submitQuiz(List<Map<String, dynamic>> questions) async {
    setState(() {
      _submittingQuiz = true;
    });

    try {
      final response = await ref.read(apiClientProvider).post(
            '/quiz/submit',
            body: {
              'article_id': widget.articleId,
              'answers': questions
                  .where((item) => _quizSelections.containsKey((item['question_id'] as num?)?.toInt() ?? -1))
                  .map(
                    (item) => {
                      'question_id': (item['question_id'] as num).toInt(),
                      'selected_option_index': _quizSelections[(item['question_id'] as num).toInt()],
                    },
                  )
                  .toList(),
            },
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (!mounted) {
        return;
      }
      setState(() {
        _quizResult = data;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交小测失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _submittingQuiz = false;
        });
      }
    }
  }

  String _normalizeLookupText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _splitIntoSentences(String text) {
    final items = RegExp(r'[^.!?]+[.!?]?')
        .allMatches(text)
        .map((match) => (match.group(0) ?? '').trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (items.isNotEmpty) {
      return items;
    }
    final normalized = text.trim();
    return normalized.isEmpty ? const <String>[] : <String>[normalized];
  }

  Map<String, String> _sentenceTranslationMap(List<Map<String, dynamic>> analyses) {
    final translations = <String, String>{};
    for (final item in analyses) {
      final sentence = _normalizeLookupText(item['sentence']?.toString() ?? '');
      final translation = item['translation']?.toString().trim() ?? '';
      if (sentence.isEmpty || translation.isEmpty) {
        continue;
      }
      translations[sentence] = translation;
    }
    return translations;
  }

  Widget _buildInteractiveParagraphText(String text) {
    final tokens = RegExp(r'[A-Za-z]+|[^A-Za-z]+').allMatches(text).map((m) => m.group(0) ?? '').toList();
    final wordRegex = RegExp(r'^[A-Za-z]+$');

    return Wrap(
      children: tokens.map((token) {
        if (!wordRegex.hasMatch(token)) {
          return Text(
            token,
            style: const TextStyle(fontSize: 16, height: 1.9, color: AppColors.textPrimary),
          );
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
              height: 1.9,
              color: color,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: color.withValues(alpha: 0.35),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _showTranslationSheet(
    Map<String, dynamic> paragraph,
    List<Map<String, dynamic>> analyses,
  ) async {
    final index = (paragraph['index'] as num?)?.toInt() ?? 1;
    final text = paragraph['text']?.toString() ?? '';
    final paragraphTranslation = paragraph['translation']?.toString() ?? '';
    final sentenceTranslationMap = _sentenceTranslationMap(analyses);
    final sentences = _splitIntoSentences(text);

    await _markProgress(index);
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第$index段  句段翻译',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text('整段中译', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpace.sm),
                  AppSectionCard(
                    color: AppColors.surfaceMuted,
                    child: Text(
                      paragraphTranslation.isNotEmpty
                          ? paragraphTranslation
                          : '这段暂时还没有单独维护中文译文。',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.75),
                    ),
                  ),
                  if (sentences.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.lg),
                    Text('句子选择', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpace.sm),
                    ...sentences.map((sentence) {
                      final normalizedSentence = _normalizeLookupText(sentence);
                      final directTranslation = sentenceTranslationMap[normalizedSentence];
                      final displayTranslation = (directTranslation != null && directTranslation.isNotEmpty)
                          ? directTranslation
                          : (sentences.length == 1 && paragraphTranslation.isNotEmpty)
                              ? paragraphTranslation
                              : paragraphTranslation.isNotEmpty
                                  ? '暂未维护单句译文，可先参考整段中译。'
                                  : '暂未维护单句译文。';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: AppSectionCard(
                          color: AppColors.surfaceMuted,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sentence, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: AppSpace.sm),
                              Text(displayTranslation, style: Theme.of(context).textTheme.bodyLarge),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArticleParagraph(
    Map<String, dynamic> paragraph,
    List<Map<String, dynamic>> analyses,
  ) {
    final index = (paragraph['index'] as num?)?.toInt() ?? 1;
    final text = paragraph['text']?.toString() ?? '';
    final translation = paragraph['translation']?.toString() ?? '';
    final showTranslation = _readingMode != _ReadingMode.english;
    final showEnglish = _readingMode != _ReadingMode.translated || translation.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => _markProgress(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusBadge(label: '第$index段'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showTranslationSheet(paragraph, analyses),
                      icon: const Icon(Icons.translate, size: 18),
                      label: const Text('句 / 段翻译'),
                    ),
                  ],
                ),
                if (showEnglish)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: _buildInteractiveParagraphText(text),
                  ),
                if (showTranslation) ...[
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      translation.isNotEmpty
                          ? translation
                          : '这段暂时还没有中文译文，先显示原文。',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSentenceAnalysisSection(List<Map<String, dynamic>> analyses) {
    if (analyses.isEmpty) {
      return const AppEmptyState(
        title: '暂无句子解析',
        subtitle: '这篇文章暂时还没有维护重点句解析。',
        icon: Icons.rule_folder_outlined,
      );
    }

    return Column(
      children: analyses.map((item) {
        final sentence = item['sentence']?.toString() ?? '-';
        final translation = item['translation']?.toString() ?? '';
        final structure = item['structure']?.toString() ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppSectionCard(
            color: AppColors.surfaceMuted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sentence, style: Theme.of(context).textTheme.titleMedium),
                if (translation.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text('翻译：$translation'),
                ],
                if (structure.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text('结构：$structure'),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  AppStatusTone _audioTone(String status) {
    switch (status) {
      case 'ready':
        return AppStatusTone.success;
      case 'processing':
        return AppStatusTone.brand;
      case 'failed':
        return AppStatusTone.danger;
      default:
        return AppStatusTone.warning;
    }
  }

  String _audioStatusLabel(String status) {
    switch (status) {
      case 'ready':
        return '音频已就绪';
      case 'processing':
        return '音频生成中';
      case 'failed':
        return '音频生成失败';
      default:
        return '音频待生成';
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildAudioSection(Map<String, dynamic> audio) {
    final status = audio['status']?.toString() ?? 'pending';
    final audioUrl = audio['article_audio_url']?.toString();
    final retryHint = audio['retry_hint']?.toString();
    final paragraphTimestamps =
        ((audio['paragraph_timestamps'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
    final estimatedDurationSeconds =
        paragraphTimestamps.isEmpty ? 0.0 : (paragraphTimestamps.last['end'] as num?)?.toDouble() ?? 0.0;

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('文章音频', style: Theme.of(context).textTheme.titleLarge),
              ),
              AppStatusBadge(label: _audioStatusLabel(status), tone: _audioTone(status)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            status == 'ready'
                ? '可以直接播放整篇文章音频，适合边听边读。'
                : status == 'failed'
                    ? '当前音频生成未成功，暂时无法播放。'
                    : '后台正在准备文章音频，生成完成后这里会开放播放。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (paragraphTimestamps.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                AppStatusBadge(label: '${paragraphTimestamps.length} 段'),
                AppStatusBadge(
                  label: '约 ${estimatedDurationSeconds.toStringAsFixed(0)} 秒',
                  tone: AppStatusTone.brand,
                ),
              ],
            ),
          ],
          if (status == 'ready' && audioUrl != null && audioUrl.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            StreamBuilder<PlayerState>(
              stream: _audioPlayer.playerStateStream,
              initialData: _audioPlayer.playerState,
              builder: (context, playerSnapshot) {
                final playerState = playerSnapshot.data ?? _audioPlayer.playerState;
                final playing = playerState.playing;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        FilledButton.icon(
                          onPressed: _audioLoading ? null : () => _toggleAudioPlayback(audioUrl),
                          icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                          label: Text(_audioLoading ? '加载中...' : (playing ? '暂停播放' : '播放音频')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadedAudioUrl == null && !_audioPlayer.playing ? null : _restartAudio,
                          icon: const Icon(Icons.replay),
                          label: const Text('从头播放'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    StreamBuilder<Duration?>(
                      stream: _audioPlayer.durationStream,
                      initialData: _audioPlayer.duration,
                      builder: (context, durationSnapshot) {
                        final total = durationSnapshot.data ?? Duration.zero;
                        return StreamBuilder<Duration>(
                          stream: _audioPlayer.positionStream,
                          initialData: _audioPlayer.position,
                          builder: (context, positionSnapshot) {
                            final position = positionSnapshot.data ?? Duration.zero;
                            final safePosition = position > total ? total : position;
                            final maxMilliseconds = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: maxMilliseconds,
                                    value: safePosition.inMilliseconds.clamp(0, maxMilliseconds.toInt()).toDouble(),
                                    onChanged: total == Duration.zero
                                        ? null
                                        : (value) => _seekAudio(value, total),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(_formatDuration(safePosition), style: Theme.of(context).textTheme.bodySmall),
                                    const Spacer(),
                                    Text(_formatDuration(total), style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ] else if (retryHint != null && retryHint.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(retryHint, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (_audioError != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _audioError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuizSection(List<Map<String, dynamic>> questions) {
    if (questions.isEmpty) {
      return const AppEmptyState(
        title: '暂无阅读小测',
        subtitle: '这篇文章还没有配置阅读理解题。',
        icon: Icons.quiz_outlined,
      );
    }

    final wrongItems = ((_quizResult?['wrong_items'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...questions.asMap().entries.map((entry) {
          final question = entry.value;
          final questionId = (question['question_id'] as num?)?.toInt() ?? 0;
          final options = ((question['options'] as List?) ?? const <dynamic>[]).map((item) => item.toString()).toList();
          final groupValue = _quizSelections[questionId];

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: AppSectionCard(
              color: AppColors.surfaceMuted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key + 1}. ${question['stem'] ?? '-'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  ...List.generate(options.length, (index) {
                    final optionValue = index + 1;
                    final selected = groupValue == optionValue;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == options.length - 1 ? 0 : AppSpace.sm,
                      ),
                      child: Material(
                        color: selected ? AppColors.brandSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => _selectQuizOption(questionId, optionValue),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpace.md),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: selected ? AppColors.brandStrong : AppColors.border,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off_outlined,
                                    size: 20,
                                    color: selected ? AppColors.brandStrong : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: AppSpace.sm),
                                Expanded(child: Text(options[index])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton(
              onPressed: _submittingQuiz ? null : () => _submitQuiz(questions),
              child: Text(_submittingQuiz ? '提交中...' : '提交小测'),
            ),
            OutlinedButton(
              onPressed: _submittingQuiz
                  ? null
                  : () {
                      setState(() {
                        _quizSelections.clear();
                        _quizResult = null;
                      });
                    },
              child: const Text('清空作答'),
            ),
          ],
        ),
        if (_quizResult != null) ...[
          const SizedBox(height: AppSpace.md),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本次结果', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    AppStatusBadge(
                      label: '正确 ${_quizResult?['correct_count'] ?? 0} / ${_quizResult?['total_count'] ?? 0}',
                      tone: AppStatusTone.success,
                    ),
                    AppStatusBadge(
                      label: '正确率 ${((_quizResult?['accuracy'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      tone: AppStatusTone.brand,
                    ),
                  ],
                ),
                if (wrongItems.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text('错题序号：${wrongItems.join('、')}'),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_audioPlayer.dispose());
    super.dispose();
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
            final translationStatus = data['translation_status']?.toString() ?? 'unavailable';
            final analyses = (data['sentence_analyses'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            final quizQuestions = (data['quiz_questions'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            final audio = (data['audio'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
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
                _buildAudioSection(audio),
                const SizedBox(height: AppSpace.lg),
                AppSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('\u6b63\u6587\u9605\u8bfb\u6a21\u5f0f', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<_ReadingMode>(
                        segments: const <ButtonSegment<_ReadingMode>>[
                          ButtonSegment<_ReadingMode>(
                            value: _ReadingMode.english,
                            label: Text('\u82f1\u6587\u539f\u6587'),
                            icon: Icon(Icons.menu_book_outlined),
                          ),
                          ButtonSegment<_ReadingMode>(
                            value: _ReadingMode.bilingual,
                            label: Text('\u4e2d\u82f1\u5bf9\u7167'),
                            icon: Icon(Icons.compare_arrows_outlined),
                          ),
                          ButtonSegment<_ReadingMode>(
                            value: _ReadingMode.translated,
                            label: Text('\u5168\u6587\u4e2d\u8bd1'),
                            icon: Icon(Icons.translate_outlined),
                          ),
                        ],
                        selected: <_ReadingMode>{_readingMode},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) {
                            return;
                          }
                          setState(() {
                            _readingMode = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        translationStatus == 'unavailable'
                            ? '\u5f53\u524d\u6587\u7ae0\u8fd8\u6ca1\u6709\u4e2d\u6587\u8bd1\u6587\uff0c\u53ef\u5148\u9605\u8bfb\u539f\u6587\u6216\u4f7f\u7528\u53e5\u6bb5\u7ffb\u8bd1\u3002'
                            : translationStatus == 'partial'
                                ? '\u5f53\u524d\u6587\u7ae0\u53ea\u7ef4\u62a4\u4e86\u90e8\u5206\u4e2d\u6587\u8bd1\u6587\uff0c\u7f3a\u5931\u6bb5\u843d\u4f1a\u7ee7\u7eed\u663e\u793a\u82f1\u6587\u3002'
                                : '\u70b9\u51fb\u5355\u8bcd\u53ef\u67e5\u8bcd\uff1b\u6bcf\u6bb5\u53f3\u4fa7\u53ef\u67e5\u770b\u53e5\u5b50\u6216\u6574\u6bb5\u7ffb\u8bd1\u3002',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text('\u6b63\u6587', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpace.sm),
                if (paragraphs.isEmpty)
                  const AppEmptyState(
                    title: '\u8fd9\u7bc7\u6587\u7ae0\u8fd8\u6ca1\u6709\u6b63\u6587\u5185\u5bb9',
                    subtitle: '\u7a0d\u540e\u5237\u65b0\u6216\u8fd4\u56de\u6587\u7ae0\u5e93\u9009\u62e9\u5176\u4ed6\u6587\u7ae0\u3002',
                    icon: Icons.article_outlined,
                  )
                else
                  AppSectionCard(
                    padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: paragraphs
                          .map((raw) => _buildArticleParagraph(raw.cast<String, dynamic>(), analyses))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: AppSpace.lg),
                Text('重点句解析', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpace.sm),
                _buildSentenceAnalysisSection(analyses),
                const SizedBox(height: AppSpace.lg),
                Text('阅读小测', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpace.sm),
                _buildQuizSection(quizQuestions),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
