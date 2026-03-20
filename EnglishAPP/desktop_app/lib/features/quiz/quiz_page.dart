import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QuizPage extends StatelessWidget {
  const QuizPage({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读小测')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1/3  What is the main idea of the article?'),
            const SizedBox(height: 12),
            ...['A', 'B', 'C', 'D'].map((e) => RadioListTile<String>(
                  value: e,
                  groupValue: null,
                  onChanged: (_) {},
                  title: Text('选项 $e'),
                )),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => context.go('/quiz/attempts/7001/result'),
                child: const Text('提交'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
