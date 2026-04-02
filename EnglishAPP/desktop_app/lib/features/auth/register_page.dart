import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_section_card.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  String _target = 'cet4';
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final api = ref.read(apiClientProvider);
    try {
      await api.post(
        '/auth/register',
        body: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'nickname': _nicknameController.text.trim(),
          'target': _target,
        },
      );

      final login = await api.post(
        '/auth/login',
        body: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );
      final data = (login['data'] as Map).cast<String, dynamic>();

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
        _errorText = '注册失败（${e.statusCode}）：${e.message}';
      });
    } catch (_) {
      setState(() {
        _errorText = '注册失败：请确认后端服务已启动（127.0.0.1:8000）';
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
            colors: [Color(0xFFFFF7EF), Color(0xFFFDFBF6), Color(0xFFFFFFFF)],
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
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '创建新账号',
                          style: theme.textTheme.labelMedium?.copyWith(color: AppColors.warning),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text('开始使用', style: AppTheme.kaitiTextStyle(theme.textTheme.headlineSmall)),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        '注册后会自动登录，并同步你的阅读进度、生词本和学习数据。',
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
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          helperText: '至少 8 位',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      TextField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(
                          labelText: '昵称',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      DropdownButtonFormField<String>(
                        initialValue: _target,
                        decoration: const InputDecoration(
                          labelText: '备考目标',
                          prefixIcon: Icon(Icons.flag_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cet4', child: Text('四级')),
                          DropdownMenuItem(value: 'cet6', child: Text('六级')),
                          DropdownMenuItem(value: 'kaoyan', child: Text('考研')),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _target = value;
                          });
                        },
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
                          onPressed: _submitting ? null : _register,
                          child: Text(_submitting ? '注册中...' : '注册并进入首页'),
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _submitting ? null : () => context.go('/login'),
                          child: const Text('已有账号，返回登录'),
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
