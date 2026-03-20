import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/analysis/analysis_page.dart';
import '../../features/articles/article_detail_page.dart';
import '../../features/articles/articles_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/home/home_page.dart';
import '../../features/me/favorites_page.dart';
import '../../features/me/me_page.dart';
import '../../features/quiz/quiz_page.dart';
import '../../features/quiz/quiz_result_page.dart';
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
        builder: (_, state) => ArticleDetailPage(articleId: state.pathParameters['articleId']!),
      ),
      GoRoute(
        path: '/articles/:articleId/analysis',
        builder: (_, state) => AnalysisPage(articleId: state.pathParameters['articleId']!),
      ),
      GoRoute(
        path: '/articles/:articleId/quiz',
        builder: (_, state) => QuizPage(articleId: state.pathParameters['articleId']!),
      ),
      GoRoute(
        path: '/quiz/attempts/:attemptId/result',
        builder: (_, state) => QuizResultPage(attemptId: state.pathParameters['attemptId']!),
      ),
      GoRoute(path: '/vocab', builder: (_, __) => const VocabPage()),
      GoRoute(path: '/me', builder: (_, __) => const MePage()),
      GoRoute(path: '/me/favorites', builder: (_, __) => const FavoritesPage()),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri.toString()}')),
    ),
  );
}
