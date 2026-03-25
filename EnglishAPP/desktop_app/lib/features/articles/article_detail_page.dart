import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/state/session_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录后可收藏文章')));
      return;
    }

    try {
      if (_favorite) {
        await api.delete('/articles/${widget.articleId}/favorite', requiresAuth: true);
      } else {
        await api.post('/articles/${widget.articleId}/favorite', requiresAuth: true);
      }
      if (!mounted) return;
      setState(() {
        _favorite = !_favorite;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('收藏失败：$e')));
    }
  }

  Future<void> _markProgress(int paragraphIndex) async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) return;

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录后可加入生词本')));
      return;
    }

    final wordId = (wordData?['id'] as num?)?.toInt();
    if (wordId == null) return;

    try {
      await api.post(
        '/vocab',
        requiresAuth: true,
        body: {'word_id': wordId, 'source_article_id': widget.articleId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入生词本')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入生词本失败：$e')));
    }
  }

  Future<void> _showWordSheet(String word) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) return;

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
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查词失败：${e.message}')));
          return;
        }
      } catch (e) {
        if (!mounted) return;
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

    if (!mounted) return;

    final found = wordData?['found'] as bool?;
    final exists = found != false && wordData != null && wordData.isNotEmpty;
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
              Text(normalized, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (!exists)
                const Text('暂未查到这个单词的中文释义，请换一个词再试。')
              else ...[
                Text('词元：${wordData?['lemma'] ?? normalized}'),
                const SizedBox(height: 6),
                Text('音标：${wordData?['phonetic'] ?? '-'}'),
                const SizedBox(height: 6),
                Text('词性：${wordData?['pos'] ?? '-'}'),
                const SizedBox(height: 6),
                Text('中文释义：${wordData?['meaning_cn'] ?? '-'}'),
                const SizedBox(height: 6),
                Text('来源：${wordData?['source'] ?? 'local'}'),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => _saveWord(wordData),
                  child: const Text('加入生词本'),
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

    return InkWell(
      onTap: () => _markProgress(paragraphIndex),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                ? Colors.orange.shade700
                : (isNotFound ? Colors.red.shade700 : Colors.blue.shade700);

            return InkWell(
              onTap: () => _showWordSheet(normalized),
              child: Text(
                token,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.8,
                  color: color,
                  decoration: TextDecoration.underline,
                ),
              ),
            );
          }).toList(),
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
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 140),
                  Center(child: Text('加载失败：${snapshot.error}')),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final paragraphs = (data['paragraphs'] as List?)?.cast<Map>() ?? const <Map>[];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(data['title']?.toString() ?? '-', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text('${data['stage']} · L${data['level']} · ${data['topic']} · ${data['reading_minutes']} 分钟'),
                const SizedBox(height: 12),
                Text(
                  data['summary']?.toString() ?? '进入正文后，点击任意英文单词即可查释义；点击段落可自动记录阅读进度。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Text('正文', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...paragraphs.map((raw) {
                  final item = raw.cast<String, dynamic>();
                  final index = (item['index'] as num?)?.toInt() ?? 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('段落 $index', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
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
