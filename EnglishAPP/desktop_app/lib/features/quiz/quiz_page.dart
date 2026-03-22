import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';

class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final Map<int, String> _answers = <int, String>{};
  bool _submitting = false;

  int get _articleId => int.tryParse(widget.articleId) ?? 0;

  @override
  void initState() {
    super.initState();
    _future = _loadQuestions();
  }

  Future<List<Map<String, dynamic>>> _loadQuestions() async {
    final api = ref.read(apiClientProvider);
    final response = await api.get('/articles/${widget.articleId}/quiz');
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final questions = (data['questions'] as List?)?.cast<Map>() ?? const <Map>[];
    return questions.map((raw) => raw.cast<String, dynamic>()).toList();
  }

  Future<void> _trackEvent(
    String eventName, {
    int? articleId,
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
          'context': contextData,
        },
      );
    } catch (_) {
      // Analytics should never block core user flows.
    }
  }

  Future<void> _submit(List<Map<String, dynamic>> questions) async {
    if (_submitting) return;

    if (_answers.length < questions.length) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先完成所有题目')));
      return;
    }

    setState(() {
      _submitting = true;
    });

    final payloadAnswers = questions
        .map(
          (q) {
            final qid = (q['question_id'] as num?)?.toInt() ?? 0;
            return {
              'question_id': qid,
              'answer': _answers[qid],
            };
          },
        )
        .toList();

    final api = ref.read(apiClientProvider);
    try {
      final response = await api.post(
        '/quiz/submit',
        body: {
          'article_id': _articleId,
          'answers': payloadAnswers,
        },
      );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final attemptId = data['attempt_id']?.toString();
      if (attemptId == null) {
        throw Exception('missing_attempt_id');
      }

      unawaited(
        _trackEvent(
          'quiz_submit',
          articleId: _articleId,
          contextData: <String, dynamic>{
            'question_count': questions.length,
            'answered_count': _answers.length,
          },
        ),
      );

      if (!mounted) return;
      context.go('/quiz/attempts/$attemptId/result');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读小测')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }

          final questions = snapshot.data ?? const <Map<String, dynamic>>[];
          if (questions.isEmpty) {
            return const Center(child: Text('暂无小测题目'));
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('共 ${questions.length} 题', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: questions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final q = questions[index];
                      final qid = (q['question_id'] as num?)?.toInt() ?? 0;
                      final options = (q['options'] as List?)?.cast<String>() ?? const <String>[];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${index + 1}. ${q['stem'] ?? '-'}'),
                              const SizedBox(height: 8),
                              ...options.map(
                                (option) => RadioListTile<String>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: option,
                                  groupValue: _answers[qid],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _answers[qid] = value;
                                    });
                                  },
                                  title: Text('选项 $option'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _submit(questions),
                    child: Text(_submitting ? '提交中...' : '提交'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
