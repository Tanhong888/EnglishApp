import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/admin_console_controller.dart';

class AdminConsolePage extends ConsumerStatefulWidget {
  const AdminConsolePage({super.key});

  @override
  ConsumerState<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends ConsumerState<AdminConsolePage> {
  final TextEditingController _adminKeyController = TextEditingController();
  final TextEditingController _articleSearchController = TextEditingController();
  final TextEditingController _wordSearchController = TextEditingController();
  late Future<Map<String, dynamic>> _articlesFuture;
  late Future<Map<String, dynamic>> _wordsFuture;
  bool? _publishedFilter;
  String _articleQuery = '';
  String _wordQuery = '';
  bool _savingAdminKey = false;
  bool _adminKeyLoaded = false;

  @override
  void initState() {
    super.initState();
    _articlesFuture = Future.value(_emptyPagedResult());
    _wordsFuture = Future.value(_emptyPagedResult());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final adminState = ref.read(adminConsoleProvider);
    if (!_adminKeyLoaded && adminState.initialized) {
      _adminKeyLoaded = true;
      _adminKeyController.text = adminState.adminApiKey ?? '';
      if (adminState.hasAdminApiKey) {
        _articlesFuture = _loadArticles();
        _wordsFuture = _loadWords();
      }
    }
  }

  @override
  void dispose() {
    _adminKeyController.dispose();
    _articleSearchController.dispose();
    _wordSearchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _emptyPagedResult() {
    return {
      'items': <Map<String, dynamic>>[],
      'page': 1,
      'size': 20,
      'total': 0,
      'has_next': false,
    };
  }

  Future<Map<String, dynamic>> _loadArticles() async {
    final api = ref.read(adminApiProvider);
    final query = <String, String>{'page': '1', 'size': '20'};
    if (_publishedFilter != null) {
      query['published'] = _publishedFilter.toString();
    }
    if (_articleQuery.trim().isNotEmpty) {
      query['q'] = _articleQuery.trim();
    }
    final response = await api.get('/admin/articles', query: query);
    return (response['data'] as Map?)?.cast<String, dynamic>() ?? _emptyPagedResult();
  }

  Future<Map<String, dynamic>> _loadWords() async {
    final api = ref.read(adminApiProvider);
    final query = <String, String>{'page': '1', 'size': '30'};
    if (_wordQuery.trim().isNotEmpty) {
      query['q'] = _wordQuery.trim();
    }
    final response = await api.get('/admin/words', query: query);
    return (response['data'] as Map?)?.cast<String, dynamic>() ?? _emptyPagedResult();
  }

  Future<void> _reloadArticles() async {
    setState(() {
      _articlesFuture = _loadArticles();
    });
    await _articlesFuture;
  }

  Future<void> _reloadWords() async {
    setState(() {
      _wordsFuture = _loadWords();
    });
    await _wordsFuture;
  }

  Future<void> _saveAdminKey() async {
    setState(() {
      _savingAdminKey = true;
    });
    try {
      await ref.read(adminConsoleProvider.notifier).setAdminApiKey(_adminKeyController.text);
      if (!mounted) return;
      setState(() {
        _articlesFuture = _loadArticles();
        _wordsFuture = _loadWords();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('管理密钥已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingAdminKey = false;
        });
      }
    }
  }

  Future<void> _clearAdminKey() async {
    await ref.read(adminConsoleProvider.notifier).clear();
    if (!mounted) return;
    _adminKeyController.clear();
    setState(() {
      _articlesFuture = Future.value(_emptyPagedResult());
      _wordsFuture = Future.value(_emptyPagedResult());
    });
  }

  Future<void> _openArticleEditor({int? articleId}) async {
    final target = articleId == null ? '/admin/articles/new' : '/admin/articles/$articleId';
    await context.push(target);
    if (!mounted) return;
    await _reloadArticles();
  }

  Future<void> _showWordEditor({Map<String, dynamic>? word}) async {
    final lemmaController = TextEditingController(text: word?['lemma']?.toString() ?? '');
    final phoneticController = TextEditingController(text: word?['phonetic']?.toString() ?? '');
    final posController = TextEditingController(text: word?['pos']?.toString() ?? '');
    final meaningController = TextEditingController(text: word?['meaning_cn']?.toString() ?? '');
    var submitting = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              setDialogState(() {
                submitting = true;
              });
              final api = ref.read(adminApiProvider);
              try {
                if (word == null) {
                  await api.post(
                    '/admin/words',
                    body: {
                      'lemma': lemmaController.text.trim(),
                      'phonetic': phoneticController.text.trim(),
                      'pos': posController.text.trim(),
                      'meaning_cn': meaningController.text.trim(),
                    },
                  );
                } else {
                  await api.patch(
                    '/admin/words/${word['id']}',
                    body: {
                      'phonetic': phoneticController.text.trim(),
                      'pos': posController.text.trim(),
                      'meaning_cn': meaningController.text.trim(),
                    },
                  );
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(true);
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('保存词汇失败：$e')));
                setDialogState(() {
                  submitting = false;
                });
              }
            }

            return AlertDialog(
              title: Text(word == null ? '新增词汇' : '编辑词汇'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: lemmaController,
                        enabled: word == null,
                        decoration: const InputDecoration(labelText: '词元 lemma'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneticController,
                        decoration: const InputDecoration(labelText: '音标'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: posController,
                        decoration: const InputDecoration(labelText: '词性'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: meaningController,
                        decoration: const InputDecoration(labelText: '中文释义'),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? '保存中...' : '保存'),
                ),
              ],
            );
          },
        );
      },
    );

    lemmaController.dispose();
    phoneticController.dispose();
    posController.dispose();
    meaningController.dispose();

    if (saved == true && mounted) {
      await _reloadWords();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('词汇已保存')));
    }
  }

  Widget _buildAdminKeyCard(AdminConsoleState adminState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '内容管理台',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '请输入 TECH_DESIGN 约定的 Admin API Key，保存后即可管理文章、解析、小测和词汇。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _adminKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Admin API Key',
                      hintText: '输入后台管理密钥',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _savingAdminKey ? null : _saveAdminKey,
                  child: Text(_savingAdminKey ? '保存中...' : '保存'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: adminState.hasAdminApiKey ? _clearAdminKey : null,
                  child: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    adminState.hasAdminApiKey ? Icons.verified_user : Icons.key_off,
                    size: 16,
                  ),
                  label: Text(adminState.hasAdminApiKey ? '已配置管理密钥' : '未配置管理密钥'),
                ),
                const Chip(label: Text('Windows 管理端 MVP')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArticlesTab() {
    return Column(
      children: [
        Row(
          children: [
            ChoiceChip(
              label: const Text('????'),
              selected: _publishedFilter == null,
              onSelected: (_) {
                setState(() {
                  _publishedFilter = null;
                  _articlesFuture = _loadArticles();
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('????'),
              selected: _publishedFilter == true,
              onSelected: (_) {
                setState(() {
                  _publishedFilter = true;
                  _articlesFuture = _loadArticles();
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('???'),
              selected: _publishedFilter == false,
              onSelected: (_) {
                setState(() {
                  _publishedFilter = false;
                  _articlesFuture = _loadArticles();
                });
              },
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _reloadArticles,
              icon: const Icon(Icons.refresh),
              label: const Text('??'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _openArticleEditor(),
              icon: const Icon(Icons.add),
              label: const Text('????'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _articleSearchController,
          decoration: InputDecoration(
            hintText: 'Search title, summary, topic, or source URL',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _articleQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _articleSearchController.clear();
                      setState(() {
                        _articleQuery = '';
                        _articlesFuture = _loadArticles();
                      });
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onSubmitted: (value) {
            setState(() {
              _articleQuery = value.trim();
              _articlesFuture = _loadArticles();
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _articlesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('加载文章失败：${snapshot.error}'));
              }

              final payload = snapshot.data ?? _emptyPagedResult();
              final items = (payload['items'] as List?)?.cast<Map>() ?? const <Map>[];
              if (items.isEmpty) {
                return const Center(child: Text('当前条件下暂无文章'));
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final article = items[index].cast<String, dynamic>();
                  final published = article['is_published'] as bool? ?? false;
                  final summary = article['summary']?.toString().trim() ?? '';
                  final sourceUrl = article['source_url']?.toString().trim() ?? '';
                  return Card(
                    child: ListTile(
                      title: Text(article['title']?.toString() ?? '-'),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${article['stage']} - Level ${article['level']} - ${article['topic']}'),
                            if (summary.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ],
                            if (sourceUrl.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                sourceUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF3554A5)),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(label: Text(published ? 'Published' : 'Draft')),
                                Chip(label: Text('Paragraphs ${article['paragraph_count'] ?? 0}')),
                                Chip(label: Text('Audio ${article['audio_status'] ?? 'pending'}')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _openArticleEditor(articleId: article['id'] as int),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWordsTab() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _wordSearchController,
                decoration: const InputDecoration(
                  hintText: '搜索 lemma / 中文释义 / 词性',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (value) {
                  setState(() {
                    _wordQuery = value;
                    _wordsFuture = _loadWords();
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _wordQuery = _wordSearchController.text;
                  _wordsFuture = _loadWords();
                });
              },
              child: const Text('搜索'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showWordEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新增词汇'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _wordsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('加载词汇失败：${snapshot.error}'));
              }

              final payload = snapshot.data ?? _emptyPagedResult();
              final items = (payload['items'] as List?)?.cast<Map>() ?? const <Map>[];
              if (items.isEmpty) {
                return const Center(child: Text('当前条件下暂无词汇'));
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final word = items[index].cast<String, dynamic>();
                  return Card(
                    child: ListTile(
                      title: Text(word['lemma']?.toString() ?? '-'),
                      subtitle: Text(
                        '${word['phonetic'] ?? '-'} · ${word['pos'] ?? '-'}\n${word['meaning_cn'] ?? '-'}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showWordEditor(word: word),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminState = ref.watch(adminConsoleProvider);

    if (!adminState.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('内容管理台'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '文章管理'),
              Tab(text: '词汇管理'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildAdminKeyCard(adminState),
              const SizedBox(height: 12),
              Expanded(
                child: adminState.hasAdminApiKey
                    ? TabBarView(
                        children: [
                          _buildArticlesTab(),
                          _buildWordsTab(),
                        ],
                      )
                    : Center(
                        child: Text(
                          '先在上方保存 Admin API Key，管理台功能才会启用。',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
