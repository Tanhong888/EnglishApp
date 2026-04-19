import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

class SessionState {
  const SessionState({
    required this.initialized,
    this.accessToken,
    this.refreshToken,
    this.user,
  });

  final bool initialized;
  final String? accessToken;
  final String? refreshToken;
  final Map<String, dynamic>? user;

  bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;

  SessionState copyWith({
    bool? initialized,
    String? accessToken,
    String? refreshToken,
    Map<String, dynamic>? user,
    bool clear = false,
  }) {
    if (clear) {
      return const SessionState(initialized: true);
    }
    return SessionState(
      initialized: initialized ?? this.initialized,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      user: user ?? this.user,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState(initialized: false)) {
    _restoreSession();
  }

  static const _kAccessTokenKey = 'session_access_token';
  static const _kRefreshTokenKey = 'session_refresh_token';
  static const _kUserKey = 'session_user';

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_kAccessTokenKey);
    final refreshToken = prefs.getString(_kRefreshTokenKey);
    final rawUser = prefs.getString(_kUserKey);

    if (accessToken == null || refreshToken == null || rawUser == null) {
      state = const SessionState(initialized: true);
      return;
    }

    try {
      final user = (jsonDecode(rawUser) as Map).cast<String, dynamic>();
      state = SessionState(
        initialized: true,
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );
    } catch (_) {
      await _clearStorage(prefs);
      state = const SessionState(initialized: true);
    }
  }

  Future<void> setSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> user,
  }) async {
    state = SessionState(
      initialized: true,
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessTokenKey, accessToken);
    await prefs.setString(_kRefreshTokenKey, refreshToken);
    await prefs.setString(_kUserKey, jsonEncode(user));
  }

  Future<void> clear() async {
    state = const SessionState(initialized: true);
    final prefs = await SharedPreferences.getInstance();
    await _clearStorage(prefs);
  }

  Future<void> updateUser(Map<String, dynamic> patch) async {
    final currentUser = state.user ?? <String, dynamic>{};
    final nextUser = <String, dynamic>{...currentUser, ...patch};
    state = state.copyWith(user: nextUser, initialized: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserKey, jsonEncode(nextUser));
  }

  Future<void> _clearStorage(SharedPreferences prefs) async {
    await prefs.remove(_kAccessTokenKey);
    await prefs.remove(_kRefreshTokenKey);
    await prefs.remove(_kUserKey);
  }
}

class AuthenticatedApi {
  AuthenticatedApi(this._ref);

  final Ref _ref;

  ApiClient get _api => _ref.read(apiClientProvider);

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool requiresAuth = false,
  }) {
    return _withAuth(
      requiresAuth: requiresAuth,
      request: (token) => _api.get(path, accessToken: token, query: query),
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool requiresAuth = false,
  }) {
    return _withAuth(
      requiresAuth: requiresAuth,
      request: (token) => _api.post(path, accessToken: token, body: body),
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    bool requiresAuth = false,
  }) {
    return _withAuth(
      requiresAuth: requiresAuth,
      request: (token) => _api.put(path, accessToken: token, body: body),
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    bool requiresAuth = false,
  }) {
    return _withAuth(
      requiresAuth: requiresAuth,
      request: (token) => _api.patch(path, accessToken: token, body: body),
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Object? body,
    bool requiresAuth = false,
  }) {
    return _withAuth(
      requiresAuth: requiresAuth,
      request: (token) => _api.delete(path, accessToken: token, body: body),
    );
  }

  Future<Map<String, dynamic>> _withAuth({
    required bool requiresAuth,
    required Future<Map<String, dynamic>> Function(String? accessToken) request,
  }) async {
    final session = _ref.read(sessionProvider);

    if (requiresAuth && !session.isAuthenticated) {
      throw ApiException(401, 'missing_authorization');
    }

    try {
      return await request(session.accessToken);
    } on ApiException catch (e) {
      if (e.statusCode != 401 || !session.isAuthenticated) {
        rethrow;
      }

      final refreshed = await _tryRefreshToken();
      if (!refreshed) {
        rethrow;
      }

      final newSession = _ref.read(sessionProvider);
      return request(newSession.accessToken);
    }
  }

  Future<bool> _tryRefreshToken() async {
    final session = _ref.read(sessionProvider);
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      return false;
    }

    try {
      final response = await _api.post(
        '/auth/refresh',
        body: {'refresh_token': session.refreshToken},
      );
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final newAccessToken = data['access_token']?.toString();
      final newRefreshToken = data['refresh_token']?.toString();
      if (newAccessToken == null || newRefreshToken == null) {
        return false;
      }

      await _ref.read(sessionProvider.notifier).setSession(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            user: session.user ?? <String, dynamic>{},
          );
      return true;
    } catch (_) {
      await _ref.read(sessionProvider.notifier).clear();
      return false;
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final authApiProvider = Provider<AuthenticatedApi>((ref) {
  return AuthenticatedApi(ref);
});

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController();
});
