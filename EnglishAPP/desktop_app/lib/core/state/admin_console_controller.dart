import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import 'session_controller.dart';

class AdminConsoleState {
  const AdminConsoleState({
    required this.initialized,
    this.adminApiKey,
  });

  final bool initialized;
  final String? adminApiKey;

  bool get hasAdminApiKey => adminApiKey != null && adminApiKey!.isNotEmpty;

  AdminConsoleState copyWith({
    bool? initialized,
    String? adminApiKey,
    bool clear = false,
  }) {
    if (clear) {
      return const AdminConsoleState(initialized: true);
    }
    return AdminConsoleState(
      initialized: initialized ?? this.initialized,
      adminApiKey: adminApiKey ?? this.adminApiKey,
    );
  }
}

class AdminConsoleController extends StateNotifier<AdminConsoleState> {
  AdminConsoleController() : super(const AdminConsoleState(initialized: false)) {
    _restore();
  }

  static const _kAdminApiKey = 'admin_api_key';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = AdminConsoleState(
      initialized: true,
      adminApiKey: prefs.getString(_kAdminApiKey),
    );
  }

  Future<void> setAdminApiKey(String value) async {
    final trimmed = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_kAdminApiKey);
      state = const AdminConsoleState(initialized: true);
      return;
    }
    await prefs.setString(_kAdminApiKey, trimmed);
    state = AdminConsoleState(initialized: true, adminApiKey: trimmed);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminApiKey);
    state = const AdminConsoleState(initialized: true);
  }
}

class AdminApi {
  AdminApi(this._ref);

  final Ref _ref;

  ApiClient get _api => _ref.read(apiClientProvider);

  Map<String, String> _adminHeaders() {
    final key = _ref.read(adminConsoleProvider).adminApiKey;
    if (key == null || key.isEmpty) {
      throw ApiException(401, 'missing_admin_api_key');
    }
    return {'X-Admin-Key': key};
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) {
    return _api.get(path, query: query, headers: _adminHeaders());
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) {
    return _api.post(path, body: body, headers: _adminHeaders());
  }

  Future<Map<String, dynamic>> put(String path, {Object? body}) {
    return _api.put(path, body: body, headers: _adminHeaders());
  }

  Future<Map<String, dynamic>> patch(String path, {Object? body}) {
    return _api.patch(path, body: body, headers: _adminHeaders());
  }
}

final adminConsoleProvider = StateNotifierProvider<AdminConsoleController, AdminConsoleState>((ref) {
  return AdminConsoleController();
});

final adminApiProvider = Provider<AdminApi>((ref) {
  return AdminApi(ref);
});
