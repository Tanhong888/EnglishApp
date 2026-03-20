import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session_controller.dart';

class AnalysisPage extends ConsumerStatefulWidget {
  const AnalysisPage({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends ConsumerState<AnalysisPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAnalyses();
  }

  Future<List<Map<String, dynamic>>> _loadAnalyses() async {
    final api = ref.read(apiClientProvider);
    final response = await api.get('/articles/${widget.articleId}/sentence-analyses');
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final items = (data['items'] as List?)?.cast<Map>() ?? const <Map>[];
    return items.map((raw) => raw.cast<String, dynamic>()).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadAnalyses();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('句子解析')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 160),
                  Center(child: Text('加载失败：${snapshot.error}')),
                ],
              );
            }

            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('暂无解析内容')),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['sentence']?.toString() ?? '-',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Text(item['translation']?.toString() ?? '-'),
                        const SizedBox(height: 8),
                        Text('结构：${item['structure'] ?? '-'}'),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
