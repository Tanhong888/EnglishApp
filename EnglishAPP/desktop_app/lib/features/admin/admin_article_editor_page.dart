import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/admin_console_controller.dart';

class AdminArticleEditorPage extends ConsumerStatefulWidget {
  const AdminArticleEditorPage({super.key, this.articleId});

  final String? articleId;

  @override
  ConsumerState<AdminArticleEditorPage> createState() => _AdminArticleEditorPageState();
}

class _AdminArticleEditorPageState extends ConsumerState<AdminArticleEditorPage> {
  static const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _sourceUrlController = TextEditingController();
  final TextEditingController _readingMinutesController = TextEditingController(text: '6');
  final TextEditingController _paragraphsController = TextEditingController();
  final TextEditingController _analysesController = TextEditingController(text: _defaultAnalysesJson);
  final TextEditingController _quizController = TextEditingController(text: _defaultQuizJson);

  bool _loading = false;
  bool _savingArticle = false;
  bool _savingAnalyses = false;
  bool _savingQuiz = false;
  bool _generatingAudio = false;
  int? _articleId;
  String _stage = 'cet4';
  int _level = 1;
  bool _isPublished = false;
  Map<String, dynamic>? _audioTask;

  static const String _defaultAnalysesJson = '''[
  {
    "sentence_index": 1,
    "sentence": "Sleep plays a major role in memory consolidation.",
    "translation": "睡眠在记忆巩固中发挥重要作用。",
    "structure": "主语 + 谓语 + role in 短语"
  }
]''';

  static const String _defaultQuizJson = '''[
  {
    "question_index": 1,
    "stem": "What does sleep help consolidate?",
    "options": ["Memory", "Color", "Weather"],
    "correct_option_index": 1
  }
]''';

  bool get _isCreateMode => widget.articleId == null;

  @override
  void initState() {
    super.initState();
    if (!_isCreateMode) {
      _articleId = int.tryParse(widget.articleId!);
      _loadArticle();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _topicController.dispose();
    _summaryController.dispose();
    _sourceUrlController.dispose();
    _readingMinutesController.dispose();
    _paragraphsController.dispose();
    _analysesController.dispose();
    _quizController.dispose();
    super.dispose();
  }

  Future<void> _loadArticle() async {
    if (_articleId == null) return;
    setState(() {
      _loading = true;
    });

    final api = ref.read(adminApiProvider);
    try {
      final articleResp = await api.get('/admin/articles/$_articleId');
      final article = (articleResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final analysesResp = await api.get('/admin/articles/$_articleId/sentence-analyses');
      final quizResp = await api.get('/admin/articles/$_articleId/quiz');
      final audioResp = await api.get('/admin/articles/$_articleId/audio-task');

      final analyses = (analysesResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final quiz = (quizResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final audio = (audioResp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final paragraphs = (article['paragraphs'] as List?)?.cast<Map>() ?? const <Map>[];
      final analysisItems = (analyses['items'] as List?)?.cast<Map>() ?? const <Map>[];
      final quizItems = (quiz['questions'] as List?)?.cast<Map>() ?? const <Map>[];

      if (!mounted) return;
      setState(() {
        _titleController.text = article['title']?.toString() ?? '';
        _topicController.text = article['topic']?.toString() ?? '';
        _summaryController.text = article['summary']?.toString() ?? '';
        _sourceUrlController.text = article['source_url']?.toString() ?? '';
        _readingMinutesController.text = (article['reading_minutes'] ?? 6).toString();
        _paragraphsController.text = paragraphs
            .map((item) => item.cast<String, dynamic>()['text']?.toString() ?? '')
            .where((text) => text.isNotEmpty)
            .join('\n\n');
        _stage = article['stage']?.toString() ?? 'cet4';
        _level = (article['level'] as num?)?.toInt() ?? 1;
        _isPublished = article['is_published'] as bool? ?? false;
        _analysesController.text = _jsonEncoder.convert(
          analysisItems.map((item) => item.cast<String, dynamic>()).map((item) {
            return {
              'sentence_index': item['sentence_index'],
              'sentence': item['sentence'],
              'translation': item['translation'],
              'structure': item['structure'],
            };
          }).toList(),
        );
        _quizController.text = _jsonEncoder.convert(
          quizItems.map((item) => item.cast<String, dynamic>()).map((item) {
            final options = (item['options'] as List?)?.cast<Map>() ?? const <Map>[];
            return {
              'question_index': item['question_index'],
              'stem': item['stem'],
              'options': options
                  .map((option) => option.cast<String, dynamic>()['content']?.toString() ?? '')
                  .where((text) => text.isNotEmpty)
                  .toList(),
              'correct_option_index': item['correct_option_index'],
            };
          }).toList(),
        );
        _audioTask = (audio['task'] as Map?)?.cast<String, dynamic>();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载文章失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<String> _parseParagraphs() {
    return _paragraphsController.text
        .split(RegExp(r'\n\s*\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _saveArticle({required bool publishAfterSave}) async {
    setState(() {
      _savingArticle = true;
    });

    try {
      final api = ref.read(adminApiProvider);
      final body = {
        'title': _titleController.text.trim(),
        'stage_tag': _stage,
        'level': _level,
        'topic': _topicController.text.trim(),
        'summary': _summaryController.text.trim(),
        'source_url': _sourceUrlController.text.trim(),
        'reading_minutes': int.tryParse(_readingMinutesController.text.trim()) ?? 6,
        'is_published': publishAfterSave ? true : _isPublished,
        'paragraphs': _parseParagraphs(),
      };

      Map<String, dynamic> response;
      if (_articleId == null) {
        response = await api.post('/admin/articles', body: body);
      } else {
        response = await api.patch('/admin/articles/$_articleId', body: body);
      }

      final article = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _articleId = article['id'] as int? ?? _articleId;
        _isPublished = article['is_published'] as bool? ?? _isPublished;
      });
      await _refreshAudioTask();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(publishAfterSave ? '文章已保存并发布' : '文章已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存文章失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingArticle = false;
        });
      }
    }
  }

  Future<void> _saveAnalyses() async {
    if (_articleId == null) return;
    setState(() {
      _savingAnalyses = true;
    });
    try {
      final decoded = jsonDecode(_analysesController.text) as List;
      final items = decoded.map((item) => (item as Map).cast<String, dynamic>()).toList();
      await ref.read(adminApiProvider).put(
            '/admin/articles/$_articleId/sentence-analyses',
            body: {'items': items},
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('句子解析已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存解析失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingAnalyses = false;
        });
      }
    }
  }

  Future<void> _saveQuiz() async {
    if (_articleId == null) return;
    setState(() {
      _savingQuiz = true;
    });
    try {
      final decoded = jsonDecode(_quizController.text) as List;
      final questions = decoded.map((item) => (item as Map).cast<String, dynamic>()).toList();
      await ref.read(adminApiProvider).put(
            '/admin/articles/$_articleId/quiz',
            body: {'questions': questions},
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('小测题已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存小测失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingQuiz = false;
        });
      }
    }
  }

  Future<void> _refreshAudioTask() async {
    if (_articleId == null) return;
    try {
      final response = await ref.read(adminApiProvider).get('/admin/articles/$_articleId/audio-task');
      final payload = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _audioTask = (payload['task'] as Map?)?.cast<String, dynamic>();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取音频任务失败：$e')));
    }
  }

  Future<void> _generateAudio() async {
    if (_articleId == null) return;
    setState(() {
      _generatingAudio = true;
    });
    try {
      await ref.read(adminApiProvider).post('/admin/articles/$_articleId/audio/generate', body: {'force': true});
      await _refreshAudioTask();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已触发音频生成任务')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('触发音频生成失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _generatingAudio = false;
        });
      }
    }
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isCreateMode ? '新建文章' : '编辑文章 #$_articleId',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text(_isPublished ? '已发布' : '草稿')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '正文段落请用空行分隔。文章保存后，解析、小测和音频任务区域才会正式生效。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _stage,
                    decoration: const InputDecoration(labelText: '阶段标签'),
                    items: const [
                      DropdownMenuItem(value: 'cet4', child: Text('CET4')),
                      DropdownMenuItem(value: 'cet6', child: Text('CET6')),
                      DropdownMenuItem(value: 'kaoyan', child: Text('考研')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _stage = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _level,
                    decoration: const InputDecoration(labelText: '难度 Level'),
                    items: const [1, 2, 3, 4]
                        .map((level) => DropdownMenuItem(value: level, child: Text('Level $level')))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _level = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _readingMinutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '阅读分钟数'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(labelText: '主题 topic'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Summary',
                alignLabelWithHint: true,
                hintText: 'Used in lists and as the imported article intro',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceUrlController,
              decoration: const InputDecoration(
                labelText: 'Source URL',
                hintText: 'Original article link',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('保存时保持发布状态'),
              subtitle: const Text('打开后保存文章会立即保持为已发布状态。'),
              value: _isPublished,
              onChanged: (value) {
                setState(() {
                  _isPublished = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paragraphsController,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: '正文段落',
                alignLabelWithHint: true,
                hintText: '每段之间空一行',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _savingArticle ? null : () => _saveArticle(publishAfterSave: false),
                  child: Text(_savingArticle ? '保存中...' : '保存文章'),
                ),
                FilledButton.tonal(
                  onPressed: _savingArticle ? null : () => _saveArticle(publishAfterSave: true),
                  child: const Text('保存并发布'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard() {
    final task = _audioTask;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('音频任务', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_articleId == null)
              const Text('请先保存文章，再触发音频生成。')
            else if (task == null)
              const Text('当前还没有音频任务记录。')
            else ...[
              Text('状态：${task['status'] ?? '-'}'),
              const SizedBox(height: 6),
              Text('尝试次数：${task['attempt_count'] ?? 0} / ${task['max_attempts'] ?? 0}'),
              if ((task['last_error']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('最近错误：${task['last_error']}'),
              ],
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _articleId == null ? null : _refreshAudioTask,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新状态'),
                ),
                FilledButton.icon(
                  onPressed: _articleId == null || _generatingAudio ? null : _generateAudio,
                  icon: const Icon(Icons.graphic_eq),
                  label: Text(_generatingAudio ? '触发中...' : '重新生成音频'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonSection({
    required String title,
    required String description,
    required TextEditingController controller,
    required VoidCallback? onSave,
    required bool saving,
    required String helper,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              helper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 10,
              maxLines: 20,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: onSave,
                child: Text(saving ? '保存中...' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isCreateMode ? '新建文章' : '编辑文章')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 12),
                _buildAudioCard(),
                const SizedBox(height: 12),
                _buildJsonSection(
                  title: '句子解析',
                  description: '按数组维护重点句解析，保存后会直接覆盖该文章下已有解析。',
                  controller: _analysesController,
                  onSave: _articleId == null || _savingAnalyses ? null : _saveAnalyses,
                  saving: _savingAnalyses,
                  helper: '字段要求：sentence_index、sentence、translation、structure。',
                ),
                const SizedBox(height: 12),
                _buildJsonSection(
                  title: '阅读小测',
                  description: '按数组维护题目，options 为选项数组，correct_option_index 从 1 开始。',
                  controller: _quizController,
                  onSave: _articleId == null || _savingQuiz ? null : _saveQuiz,
                  saving: _savingQuiz,
                  helper: '字段要求：question_index、stem、options、correct_option_index。',
                ),
              ],
            ),
    );
  }
}
