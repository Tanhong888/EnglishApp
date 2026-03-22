import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? 'http://127.0.0.1:8000/api/v1';

  final String _baseUrl;

  Future<Map<String, dynamic>> get(
    String path, {
    String? accessToken,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    return _send('GET', uri, accessToken: accessToken, headers: headers);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    String? accessToken,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    return _send('POST', uri, accessToken: accessToken, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    String? accessToken,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    return _send('PUT', uri, accessToken: accessToken, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    String? accessToken,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    return _send('PATCH', uri, accessToken: accessToken, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    String? accessToken,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    return _send('DELETE', uri, accessToken: accessToken, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    String? accessToken,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (accessToken != null && accessToken.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      }
      if (headers != null) {
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      final decoded = responseText.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(responseText) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      final detail = decoded['detail']?.toString() ?? decoded['message']?.toString() ?? 'request_failed';
      throw ApiException(response.statusCode, detail);
    } finally {
      client.close(force: true);
    }
  }
}
