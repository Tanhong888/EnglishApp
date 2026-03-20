import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('英阅通', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('Windows 桌面版 V1'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go(session.isAuthenticated ? '/home' : '/login'),
              child: Text(session.isAuthenticated ? '进入首页' : '进入登录'),
            ),
          ],
        ),
      ),
    );
  }
}
