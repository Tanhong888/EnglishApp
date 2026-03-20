import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ArticleDetailPage extends StatelessWidget {
  const ArticleDetailPage({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读详情')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'How Sleep Shapes Memory',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Level 1 · CET4 · 6 分钟'),
            const SizedBox(height: 16),
            const Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'Sleep plays a major role in memory consolidation. '
                  'Students with better sleep quality often perform better in reading tasks. '
                  'Click words for quick meaning and continue learning in context.',
                  style: TextStyle(height: 1.6, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () {}, child: const Text('全文播放')),
              OutlinedButton(onPressed: () {}, child: const Text('分段播放')),
              OutlinedButton(
                onPressed: () => context.go('/articles/$articleId/analysis'),
                child: const Text('句子解析'),
              ),
              OutlinedButton(onPressed: () {}, child: const Text('加入生词本')),
              FilledButton(
                onPressed: () => context.go('/articles/$articleId/quiz'),
                child: const Text('开始小测'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
