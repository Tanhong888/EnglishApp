import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final api = ref.read(apiClientProvider);
    final detail = await api.get('/articles/${widget.articleId}');
    final audio = await api.get('/articles/${widget.articleId}/audio');
    return {
      'detail': detail,
      'audio': audio,
    };
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

    final api = ref.read(apiClientProvider);
    try {
      if (_isFavorited) {
        await api.delete('/articles/${widget.articleId}/favorite', accessToken: session.accessToken);
      } else {
        await api.post('/articles/${widget.articleId}/favorite', accessToken: session.accessToken);
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
              OutlinedButton(onPressed: () {}, child: const Text('全文播放')),
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

