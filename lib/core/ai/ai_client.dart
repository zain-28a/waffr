// HTTP calls to the backend's /ai routes. The backend holds the model key;
// the app only sends the signed-in user's token.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:waffr/core/sync/api_config.dart';
import 'package:waffr/core/sync/auth_session.dart';

enum AiFailure {
  // Guest mode or an expired session: AI needs an account.
  signedOut,
  // Today's quota is spent.
  limited,
  // No network, a slow server, or AI switched off on the server.
  unavailable,
}

class AiException implements Exception {
  final AiFailure failure;

  const AiException(this.failure);

  @override
  String toString() => 'AiException($failure)';
}

class AiClient {
  AiClient._();

  static final AiClient instance = AiClient._();

  static const Duration _timeout = Duration(seconds: 45);

  /// POSTs [body] to [path] and returns the decoded JSON map.
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final token = await AuthSession.instance.token();
    if (token == null) throw const AiException(AiFailure.signedOut);

    final http.Response response;
    try {
      final base = await ApiConfig.baseUrl();
      response = await http
          .post(
            Uri.parse('$base$path'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.timeoutFor(base, local: _timeout));
    } catch (_) {
      throw const AiException(AiFailure.unavailable);
    }

    switch (response.statusCode) {
      case 200:
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) return decoded;
        throw const AiException(AiFailure.unavailable);
      case 401:
        throw const AiException(AiFailure.signedOut);
      case 429:
        throw const AiException(AiFailure.limited);
      default:
        throw const AiException(AiFailure.unavailable);
    }
  }
}
