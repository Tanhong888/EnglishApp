import 'package:flutter/material.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏文章')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: ListTile(
              title: Text('How Sleep Shapes Memory'),
              subtitle: Text('收藏于 2026-03-18 22:00'),
            ),
          ),
          SizedBox(height: 8),
          Card(
            child: ListTile(
              title: Text('AI and Education Equity'),
              subtitle: Text('收藏于 2026-03-19 09:30'),
            ),
          ),
        ],
      ),
    );
  }
}
