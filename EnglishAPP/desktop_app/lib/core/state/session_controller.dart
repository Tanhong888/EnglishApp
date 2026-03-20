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

  Future<void> _clearStorage(SharedPreferences prefs) async {
    await prefs.remove(_kAccessTokenKey);
    await prefs.remove(_kRefreshTokenKey);
    await prefs.remove(_kUserKey);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController();
});
