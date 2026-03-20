import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Center(
        child: SizedBox(
          width: 360,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TextField(decoration: InputDecoration(labelText: '邮箱')),
                  const SizedBox(height: 12),
                  const TextField(decoration: InputDecoration(labelText: '密码'), obscureText: true),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('模拟登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
