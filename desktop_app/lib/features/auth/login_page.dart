import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_section_card.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController(text: 'demo@englishapp.dev');
  final _passwordController = TextEditingController(text: 'Passw0rd!');
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final api = ref.read(apiClientProvider);
    try {
      final response = await api.post(
        '/auth/login',
        body: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );
      final data = (response['data'] as Map).cast<String, dynamic>();

      await ref.read(sessionProvider.notifier).setSession(
            accessToken: data['access_token'] as String,
            refreshToken: data['refresh_token'] as String,
            user: (data['user'] as Map).cast<String, dynamic>(),
          );

      if (!mounted) {
        return;
      }
      context.go('/home');
    } on ApiException catch (e) {
      setState(() {
        _errorText = '登录失败（${e.statusCode}）：${e.message}';
      });
    } catch (_) {
      setState(() {
        _errorText = '登录失败：请确认后端服务已启动（127.0.0.1:8000）';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF2F6FF), Color(0xFFF7F8FA), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppWidth.form),
                child: AppSectionCard(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'Windows 桌面端',
                          style: theme.textTheme.labelMedium?.copyWith(color: AppColors.brandStrong),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text('欢迎回来', style: AppTheme.kaitiTextStyle(theme.textTheme.headlineSmall)),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        '登录后即可同步阅读进度、生词本和个人学习数据。',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpace.xl),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: '邮箱',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        onSubmitted: (_) => _submitting ? null : _login(),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: AppSpace.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpace.sm),
                          decoration: BoxDecoration(
                            color: AppColors.errorSoft,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            _errorText!,
                            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _login,
                          child: Text(_submitting ? '登录中...' : '登录并进入首页'),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Text(
                        '开发演示账号：demo@englishapp.dev / Passw0rd!',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _submitting ? null : () => context.go('/register'),
                          child: const Text('没有账号？立即注册'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
