import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/tokens.dart';
import 'app_section_card.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F7FF), Color(0xFFF7F8FA), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppWidth.form),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: AppSectionCard(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.auto_stories_outlined, color: AppColors.brandStrong, size: 28),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Text('英阅通', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '简洁稳定的英语阅读桌面端。',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      session.initialized
                          ? '已完成本地会话检查，可以继续进入应用。'
                          : '正在初始化本地会话与登录状态，请稍候。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    if (!session.initialized) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: AppSpace.sm),
                      const Center(child: Text('正在初始化会话...')),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.go(session.isAuthenticated ? '/home' : '/login'),
                          child: Text(session.isAuthenticated ? '进入首页' : '进入登录'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
