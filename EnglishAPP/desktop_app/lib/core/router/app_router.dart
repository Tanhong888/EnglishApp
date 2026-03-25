import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_article_editor_page.dart';
import '../../features/admin/admin_content_page.dart';
import '../../features/articles/article_detail_page.dart';
import '../../features/articles/articles_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/home/home_page.dart';
import '../../features/me/analytics_page.dart';
import '../../features/me/me_page.dart';
import '../../features/me/settings_page.dart';
import '../../features/vocab/vocab_detail_page.dart';
import '../../features/vocab/vocab_page.dart';
import '../../shared/widgets/splash_page.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(path: '/articles', builder: (_, __) => const ArticlesPage()),
      GoRoute(
        path: '/articles/:articleId',
        builder: (_, state) => ArticleDetailPage(articleId: int.parse(state.pathParameters['articleId']!)),
      ),
      GoRoute(path: '/admin/content', builder: (_, __) => const AdminContentPage()),
      GoRoute(path: '/admin/articles/new', builder: (_, __) => const AdminArticleEditorPage()),
      GoRoute(
        path: '/admin/articles/:articleId',
        builder: (_, state) => AdminArticleEditorPage(articleId: int.parse(state.pathParameters['articleId']!)),
      ),
      GoRoute(path: '/vocab', builder: (_, __) => const VocabPage()),
      GoRoute(
        path: '/vocab/:entryId',
        builder: (_, state) => VocabDetailPage(entryId: state.pathParameters['entryId']!),
      ),
      GoRoute(path: '/me', builder: (_, __) => const MePage()),
      GoRoute(path: '/me/analytics', builder: (_, __) => const MeAnalyticsPage()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri.toString()}')),
    ),
  );
}

