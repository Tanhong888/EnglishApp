import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

class SessionState {
  const SessionState({
    this.accessToken,
    this.refreshToken,
    this.user,
  });

  final String? accessToken;
  final String? refreshToken;
  final Map<String, dynamic>? user;

  bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;

  SessionState copyWith({
    String? accessToken,
    String? refreshToken,
    Map<String, dynamic>? user,
    bool clear = false,
  }) {
    if (clear) {
      return const SessionState();
    }
    return SessionState(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      user: user ?? this.user,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState());

  void setSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> user,
  }) {
    state = SessionState(accessToken: accessToken, refreshToken: refreshToken, user: user);
  }

  void clear() {
    state = const SessionState();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController();
});
