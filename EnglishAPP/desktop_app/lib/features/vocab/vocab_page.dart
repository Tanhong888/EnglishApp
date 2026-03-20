import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/app_bottom_nav.dart';

class VocabPage extends StatelessWidget {
  const VocabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return Scaffold(
      appBar: AppBar(title: const Text('生词本')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索生词')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: const [
              Chip(label: Text('全部来源')),
              Chip(label: Text('文章 #1')),
              Chip(label: Text('文章 #2')),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('consolidate'),
              subtitle: const Text('vt. 巩固；使加强 · 来源 2 篇'),
              trailing: OutlinedButton(onPressed: null, child: Text('标记掌握')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
