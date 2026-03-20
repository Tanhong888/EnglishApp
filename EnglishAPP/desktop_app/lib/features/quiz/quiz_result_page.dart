import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QuizResultPage extends StatelessWidget {
  const QuizResultPage({super.key, required this.attemptId});

  final String attemptId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小测结果')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('正确率 66%', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('错题回顾：第 1 题'),
            const Spacer(),
            Row(
              children: [
                OutlinedButton(onPressed: () => context.go('/articles'), child: const Text('返回文章列表')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => context.go('/articles/2'), child: const Text('下一篇推荐')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
