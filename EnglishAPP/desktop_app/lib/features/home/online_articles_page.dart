import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/external_link_opener.dart';
import '../../core/state/admin_console_controller.dart';
import '../../core/state/session_controller.dart';

class OnlineArticlesPage extends ConsumerStatefulWidget {
  const OnlineArticlesPage({super.key});

  @override
  ConsumerState<OnlineArticlesPage> createState() => _OnlineArticlesPageState();
}

class _OnlineArticlesPageState extends ConsumerState<OnlineArticlesPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _importingUrls = <String>{};
  int _page = 1;
  final int _size = 10;
  String _query = '';
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadResults();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadResults() async {
    final api = ref.read(apiClientProvider);
    final query = <String, String>{
      'page': _page.toString(),
      'size': _size.toString(),
    };
    if (_query.trim().isNotEmpty) {
      query['q'] = _query.trim();
    }

    final response = await api.get('/web-articles/search', query: query);
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];

    return {
      'items': items.map((raw) => raw.cast<String, dynamic>()).toList(),
      'page': (data['page'] as num?)?.toInt() ?? _page,
      'size': (data['size'] as num?)?.toInt() ?? _size,
      'total': (data['total'] as num?)?.toInt() ?? 0,
      'has_next': data['has_next'] as bool? ?? false,
      'query': data['query']?.toString() ?? _query,
      'sources_checked': (data['sources_checked'] as num?)?.toInt() ?? 0,
      'source_errors': (data['source_errors'] as List?)?.cast<String>() ?? const <String>[],
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadResults();
    });
    await _future;
  }

  void _search({String? query, int? page}) {
    setState(() {
      if (query != null) {
        _query = query.trim();
        _page = 1;
      }
      if (page != null) {
        _page = page;
      }
      _future = _loadResults();
    });
  }

  String _formatPublishedAt(String? raw) {
    if (raw == null || raw.isEmpty) return 'Unknown publish time';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Source URL copied')));
  }

  Future<void> _openUrl(String url) async {
    final opened = await openExternalUrl(url);
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser automatically. Copy the link instead.')),
      );
    }
  }

  Future<void> _importArticle(Map<String, dynamic> item) async {
    final adminState = ref.read(adminConsoleProvider);
    if (!adminState.hasAdminApiKey) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configure the Admin API Key in the admin console before importing.')),
      );
      await context.push('/admin');
      return;
    }

    final url = item['url']?.toString() ?? '';
    if (url.isEmpty) return;

    setState(() {
      _importingUrls.add(url);
    });

    try {
      final response = await ref.read(adminApiProvider).post(
            '/web-articles/import',
            body: {
              'title': item['title']?.toString() ?? 'Untitled',
              'url': url,
              'source': item['source']?.toString() ?? 'Unknown source',
              'summary': item['summary']?.toString() ?? '',
              'published_at': item['published_at']?.toString(),
            },
          );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final articleId = (data['article_id'] as num?)?.toInt();
      final imported = data['imported'] as bool? ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(imported ? 'Draft imported. Opening editor...' : 'Article already exists. Opening editor...')),
      );
      if (articleId != null) {
        await context.push('/admin/articles/$articleId');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _importingUrls.remove(url);
        });
      }
    }
  }

  Widget _buildAdminImportHint(AdminConsoleState adminState) {
    final hasKey = adminState.hasAdminApiKey;
    return Card(
      color: hasKey ? const Color(0xFFEAF6EE) : const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasKey ? Icons.verified_user : Icons.admin_panel_settings_outlined,
              color: hasKey ? const Color(0xFF256F46) : const Color(0xFF9A6700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasKey
                    ? 'Admin key is ready. You can import any result below as a draft and continue editing it in the content console.'
                    : 'Configure the Admin API Key first, then web articles here can be imported as editable drafts.',
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => context.push('/admin'),
              child: Text(hasKey ? 'Open Admin' : 'Configure'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminState = ref.watch(adminConsoleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Online Articles')),
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
                  const SizedBox(height: 120),
                  Center(child: Text('Load failed: ${snapshot.error}')),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            final total = (data['total'] as num?)?.toInt() ?? 0;
            final currentPage = (data['page'] as num?)?.toInt() ?? _page;
            final size = (data['size'] as num?)?.toInt() ?? _size;
            final hasNext = data['has_next'] as bool? ?? false;
            final sourcesChecked = (data['sources_checked'] as num?)?.toInt() ?? 0;
            final sourceErrors = (data['source_errors'] as List?)?.cast<String>() ?? const <String>[];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Public English news feeds are aggregated here as lightweight reading leads. Use them as source material before curating formal learning content.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _buildAdminImportHint(adminState),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Try keywords like sleep, education, or technology',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _search(query: '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) => _search(query: value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => _search(query: _searchController.text),
                      child: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: Text(_query.isEmpty ? 'Latest aggregated results' : 'Query: $_query'),
                    subtitle: Text('Checked $sourcesChecked feeds, showing $total results'),
                  ),
                ),
                if (sourceErrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Card(
                      color: const Color(0xFFFFF7E8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('${sourceErrors.length} feeds failed this round. Successful feed results are still shown below.'),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No results right now'),
                      subtitle: Text('Try another keyword or clear the query to see the default feed aggregation.'),
                    ),
                  ),
                ...items.map(
                  (item) {
                    final summary = (item['summary']?.toString() ?? '').trim();
                    final url = item['url']?.toString() ?? '';
                    final importing = _importingUrls.contains(url);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextButton(
                                onPressed: url.isEmpty ? null : () => _openUrl(url),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                                child: Text(
                                  item['title']?.toString() ?? '-',
                                  textAlign: TextAlign.left,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${item['source'] ?? 'Unknown source'} - ${_formatPublishedAt(item['published_at']?.toString())}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 10),
                              Text(summary.isNotEmpty ? summary : 'No summary is available from this feed item yet.'),
                              const SizedBox(height: 12),
                              SelectableText(
                                url.isNotEmpty ? url : '-',
                                style: const TextStyle(color: Color(0xFF3554A5)),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                children: [
                                  FilledButton.icon(
                                    onPressed: url.isEmpty ? null : () => _openUrl(url),
                                    icon: const Icon(Icons.open_in_browser, size: 18),
                                    label: const Text('Open Source'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: url.isEmpty || importing ? null : () => _importArticle(item),
                                    icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                                    label: Text(importing ? 'Importing...' : 'Import Draft'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: url.isEmpty ? null : () => _copyUrl(url),
                                    icon: const Icon(Icons.link, size: 18),
                                    label: const Text('Copy Link'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: currentPage > 1 ? () => _search(page: currentPage - 1) : null,
                          child: const Text('Previous'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Page $currentPage ? $size per page ? $total total',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: hasNext ? () => _search(page: currentPage + 1) : null,
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
