import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session_controller.dart';

class QuizResultPage extends ConsumerStatefulWidget {
  const QuizResultPage({super.key, required this.attemptId});

  final String attemptId;

  @override
  ConsumerState<QuizResultPage> createState() => _QuizResultPageState();
}

class _QuizResultPageState extends ConsumerState<QuizResultPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadResult();
  }

  Future<Map<String, dynamic>> _loadResult() async {
    final api = ref.read(apiClientProvider);
    final response = await api.get('/quiz/attempts/${widget.attemptId}');
    return (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小测结果')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final correct = (data['correct_count'] as num?)?.toInt() ?? 0;
          final total = (data['total_count'] as num?)?.toInt() ?? 0;
          final accuracy = ((data['accuracy'] as num?)?.toDouble() ?? 0) * 100;
          final wrongItems = (data['wrong_items'] as List?)?.cast<num>().map((n) => n.toInt()).toList() ?? const <int>[];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正确率 ${accuracy.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text('答对 $correct / $total 题'),
                const SizedBox(height: 8),
                Text(
                  wrongItems.isEmpty ? '错题回顾：无' : '错题回顾：第 ${wrongItems.join('、')} 题',
                ),
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
          );
        },
      ),
    );
  }
}
