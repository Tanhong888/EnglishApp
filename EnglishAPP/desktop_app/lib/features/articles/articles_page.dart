import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/app_bottom_nav.dart';

class ArticlesPage extends StatelessWidget {
  const ArticlesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return Scaffold(
      appBar: AppBar(title: const Text('分级阅读')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              Chip(label: Text('四级')),
              Chip(label: Text('六级')),
              Chip(label: Text('考研')),
              Chip(label: Text('Level 1')),
              Chip(label: Text('Level 2')),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('How Sleep Shapes Memory'),
              subtitle: const Text('CET4 · Level 1 · Health'),
              onTap: () => context.go('/articles/1'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('AI and Education Equity'),
              subtitle: const Text('考研 · Level 3 · Education'),
              onTap: () => context.go('/articles/3'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
