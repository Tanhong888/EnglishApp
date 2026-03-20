import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/app_bottom_nav.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return Scaffold(
      appBar: AppBar(title: const Text('首页')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('今日推荐', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('How Sleep Shapes Memory'),
              subtitle: const Text('Level 1 · CET4 · 6 分钟'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.go('/articles/1'),
            ),
          ),
          const SizedBox(height: 20),
          const Text('最近学习', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('The Science of Urban Trees'),
              subtitle: const Text('上次阅读：今天 10:00'),
              onTap: () => context.go('/articles/2'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(location: location),
    );
  }
}
