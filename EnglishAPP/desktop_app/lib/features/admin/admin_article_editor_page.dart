import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/admin_console_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_page_scroll_view.dart';
import '../../shared/widgets/app_section_card.dart';
import '../../shared/widgets/app_state_views.dart';
import '../../shared/widgets/app_status_badge.dart';

class AdminArticleEditorPage extends ConsumerStatefulWidget {
  const AdminArticleEditorPage({super.key, this.articleId});

  final int? articleId;

  @override
  ConsumerState<AdminArticleEditorPage> createState() => _AdminArticleEditorPageState();
}

class _AdminArticleEditorPageState extends ConsumerState<AdminArticleEditorPage> {
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _sourceUrlController = TextEditingController();
  final TextEditingController _readingMinutesController = TextEditingController(text: '6');
  final TextEditingController _paragraphsController = TextEditingController();
  final TextEditingController _analysesController = TextEditingController(text: '[]');
  final TextEditingController _quizController = TextEditingController(text: '[]');

  bool _loading = false;
  bool _savingArticle = false;
  bool _savingAnalyses = false;
  bool _savingQuiz = false;
  bool _refreshingAudio = false;
  int? _articleId;
  String _stage = 'cet4';
  int _level = 1;
  bool _isPublished = false;
  bool _desiredPublished = false;
  Map<String, dynamic>? _audioTask;

  bool get _isCreateMode => widget.articleId == null;

  @override
  void initState() {
    super.initState();
    _articleId = widget.articleId;
    if (_articleId != null) {
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
    final articleId = _articleId;
    if (articleId == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final api = ref.read(adminApiProvider);
      final articleResponse = await api.get('/admin/articles/$articleId');
      final analysesResponse = await api.get('/admin/articles/$articleId/sentence-analyses');
      final quizResponse = await api.get('/admin/articles/$articleId/quiz');
      final audioResponse = await api.get('/admin/articles/$articleId/audio-task');

      final article = (articleResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final analyses = (analysesResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final quiz = (quizResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final audio = (audioResponse['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final paragraphs = (article['paragraphs'] as List?)?.cast<Map>() ?? const <Map>[];
      final analysisItems = (analyses['items'] as List?)?.cast<Map>() ?? const <Map>[];
      final quizItems = (quiz['questions'] as List?)?.cast<Map>() ?? const <Map>[];

      if (!mounted) {
        return;
      }

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
        _desiredPublished = _isPublished;
        _analysesController.text = _encoder.convert(
          analysisItems.map((item) => item.cast<String, dynamic>()).toList(),
        );
        _quizController.text = _encoder.convert(
          quizItems.map((item) => item.cast<String, dynamic>()).toList(),
        );
        _audioTask = (audio['task'] as Map?)?.cast<String, dynamic>();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
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

  Future<void> _saveArticle() async {
    final title = _titleController.text.trim();
    final topic = _topicController.text.trim();
    final paragraphs = _parseParagraphs();
    if (title.isEmpty || topic.isEmpty || paragraphs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标题、主题和正文段落不能为空')));
      return;
    }

    setState(() {
      _savingArticle = true;
    });

    try {
      final api = ref.read(adminApiProvider);
      final body = <String, dynamic>{
        'title': title,
        'stage_tag': _stage,
        'level': _level,
        'topic': topic,
        'summary': _summaryController.text.trim(),
        'source_url': _sourceUrlController.text.trim(),
        'reading_minutes': int.tryParse(_readingMinutesController.text.trim()) ?? 6,
        'paragraphs': paragraphs,
      };

      Map<String, dynamic> response;
      if (_articleId == null) {
        response = await api.post(
          '/admin/articles',
          body: {
            ...body,
            'is_published': _desiredPublished,
          },
        );
      } else {
        response = await api.patch('/admin/articles/$_articleId', body: body);
      }

      var article = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final nextArticleId = (article['id'] as num?)?.toInt() ?? _articleId;
      if (_articleId != null && _desiredPublished != _isPublished) {
        final publishResponse = await api.post(
          '/admin/articles/$nextArticleId/publish',
          body: {'is_published': _desiredPublished},
        );
        article = (publishResponse['data'] as Map?)?.cast<String, dynamic>() ?? article;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _articleId = (article['id'] as num?)?.toInt() ?? nextArticleId;
        _isPublished = article['is_published'] as bool? ?? _desiredPublished;
        _desiredPublished = _isPublished;
      });
      await _loadArticle();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isPublished ? '文章已保存并发布到阅读库' : '文章草稿已保存')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
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
    final articleId = _articleId;
    if (articleId == null) {
      return;
    }

    setState(() {
      _savingAnalyses = true;
    });

    try {
      final decoded = jsonDecode(_analysesController.text) as List;
      final items = decoded.map((item) => (item as Map).cast<String, dynamic>()).toList();
      await ref.read(adminApiProvider).put(
            '/admin/articles/$articleId/sentence-analyses',
            body: {'items': items},
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('句子解析已保存')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存句子解析失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingAnalyses = false;
        });
      }
    }
  }

  Future<void> _saveQuiz() async {
    final articleId = _articleId;
    if (articleId == null) {
      return;
    }

    setState(() {
      _savingQuiz = true;
    });

    try {
      final decoded = jsonDecode(_quizController.text) as List;
      final questions = decoded.map((item) => (item as Map).cast<String, dynamic>()).toList();
      await ref.read(adminApiProvider).put(
            '/admin/articles/$articleId/quiz',
            body: {'questions': questions},
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('阅读小测已保存')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存阅读小测失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingQuiz = false;
        });
      }
    }
  }

  Future<void> _refreshAudioTask() async {
    final articleId = _articleId;
    if (articleId == null) {
      return;
    }

    setState(() {
      _refreshingAudio = true;
    });

    try {
      final response = await ref.read(adminApiProvider).get('/admin/articles/$articleId/audio-task');
      final payload = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (!mounted) {
        return;
      }
      setState(() {
        _audioTask = (payload['task'] as Map?)?.cast<String, dynamic>();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取音频任务失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _refreshingAudio = false;
        });
      }
    }
  }

  Widget _buildHeaderCard() {
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.xl),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF4F8FF), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _articleId == null ? '新建阅读文章' : '编辑文章 #$_articleId',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        '正文段落用空行分隔。文章保存后，可以继续维护句子解析和阅读小测。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                AppStatusBadge(
                  label: _isPublished ? '已发布' : '草稿',
                  tone: _isPublished ? AppStatusTone.success : AppStatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: AppSpace.md),
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
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _stage = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _level,
                    decoration: const InputDecoration(labelText: '难度等级'),
                    items: const [1, 2, 3, 4]
                        .map((level) => DropdownMenuItem(value: level, child: Text('Level $level')))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _level = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: TextField(
                    controller: _readingMinutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '阅读分钟数'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(labelText: '主题 topic'),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _summaryController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '摘要',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _sourceUrlController,
              decoration: const InputDecoration(labelText: '来源链接'),
            ),
            const SizedBox(height: AppSpace.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('保存后发布到阅读库'),
              subtitle: const Text('打开后，学习者可以在文章库中看到并开始阅读。'),
              value: _desiredPublished,
              onChanged: (value) {
                setState(() {
                  _desiredPublished = value;
                });
              },
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _paragraphsController,
              minLines: 8,
              maxLines: 18,
              decoration: const InputDecoration(
                labelText: '正文段落',
                hintText: '每段之间空一行',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                FilledButton(
                  onPressed: _savingArticle ? null : _saveArticle,
                  child: Text(_savingArticle ? '保存中...' : '保存文章'),
                ),
                OutlinedButton(
                  onPressed: _articleId == null ? null : _loadArticle,
                  child: const Text('重新加载'),
                ),
                if (_isPublished && _articleId != null)
                  OutlinedButton(
                    onPressed: () => context.push('/articles/${_articleId!}'),
                    child: const Text('打开阅读页'),
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
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('朗读音频状态', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.sm),
          if (_articleId == null)
            const Text('先保存文章，音频任务才会出现。')
          else if (task == null)
            const Text('当前没有音频任务。首次发布后会自动进入生成流程。')
          else ...[
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                AppStatusBadge(label: '状态 ${task['status'] ?? '-'}', tone: AppStatusTone.brand),
                AppStatusBadge(label: '尝试 ${task['attempt_count'] ?? 0} / ${task['max_attempts'] ?? 0}'),
              ],
            ),
            if ((task['last_error']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text('最近错误：${task['last_error']}'),
            ],
            if ((task['article_audio_url']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text('音频地址：${task['article_audio_url']}'),
            ],
          ],
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: _articleId == null || _refreshingAudio ? null : _refreshAudioTask,
            icon: const Icon(Icons.refresh),
            label: Text(_refreshingAudio ? '刷新中...' : '刷新音频状态'),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonCard({
    required String title,
    required String description,
    required String helper,
    required TextEditingController controller,
    required bool saving,
    required VoidCallback? onSave,
  }) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(description),
          const SizedBox(height: AppSpace.sm),
          Text(
            helper,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: controller,
            minLines: 10,
            maxLines: 18,
            decoration: const InputDecoration(alignLabelWithHint: true),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.tonal(
            onPressed: onSave,
            child: Text(saving ? '保存中...' : '保存配置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminState = ref.watch(adminConsoleProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreateMode ? '新建文章' : '编辑文章'),
      ),
      body: !adminState.initialized
          ? const AppPageScrollView(
              children: [
                SizedBox(height: 140),
                AppLoadingView(label: '正在初始化后台环境...'),
              ],
            )
          : !adminState.hasAdminApiKey
              ? AppPageScrollView(
                  children: [
                    const SizedBox(height: 140),
                    AppEmptyState(
                      title: '还没有配置 Admin Key',
                      subtitle: '请先返回内容运营页保存管理密钥，再进入文章编辑。',
                      icon: Icons.admin_panel_settings_outlined,
                      actionLabel: '返回内容运营页',
                      onAction: () => context.pop(),
                    ),
                  ],
                )
              : _loading
                  ? const AppPageScrollView(
                      children: [
                        SizedBox(height: 140),
                        AppLoadingView(label: '正在加载文章配置...'),
                      ],
                    )
                  : AppPageScrollView(
                      maxWidth: AppWidth.wide,
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: AppSpace.lg),
                        _buildAudioCard(),
                        const SizedBox(height: AppSpace.lg),
                        _buildJsonCard(
                          title: '句子解析',
                          description: '这里维护阅读页里重点句的翻译和结构说明，保存会覆盖现有解析。',
                          helper: 'JSON 数组字段: sentence_index, sentence, translation, structure。',
                          controller: _analysesController,
                          saving: _savingAnalyses,
                          onSave: _articleId == null || _savingAnalyses ? null : _saveAnalyses,
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _buildJsonCard(
                          title: '阅读小测',
                          description: '这里配置文章阅读后的理解题，options 为字符串数组，correct_option_index 从 1 开始。',
                          helper: 'JSON 数组字段: question_index, stem, options, correct_option_index。',
                          controller: _quizController,
                          saving: _savingQuiz,
                          onSave: _articleId == null || _savingQuiz ? null : _saveQuiz,
                        ),
                      ],
                    ),
    );
  }
}
