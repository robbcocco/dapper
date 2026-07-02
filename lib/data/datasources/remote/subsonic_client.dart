import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/errors/app_exception.dart';

// Cryptographically-strong RNG used for the salt suffix. Shared so we don't
// reseed on every request.
final _saltRng = Random.secure();

String _generateSalt() {
  // Millisecond timestamp + 32 random bits, both base-36, so two requests in
  // the same millisecond can't produce identical salt+token pairs.
  final ms = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final suffix = _saltRng.nextInt(1 << 32).toRadixString(36);
  return '$ms$suffix';
}

class SubsonicClient {
  SubsonicClient({
    required String baseUrl,
    required String username,
    required String password,
  }) : _baseUrl = baseUrl,
       _username = username,
       _password = password {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ))
      ..interceptors.add(_AuthInterceptor(username, password))
      ..interceptors.add(_SubsonicErrorInterceptor());
  }

  final String _baseUrl;
  final String _username;
  final String _password;
  late final Dio _dio;

  Dio get dio => _dio;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: params,
    );
    return response.data!['subsonic-response'] as Map<String, dynamic>;
  }

  /// Closes the underlying Dio instance. Called by the provider when this
  /// client is replaced (server switch / sign-out) so in-flight requests are
  /// cancelled and the HTTP connection pool is released.
  void dispose() {
    _dio.close(force: true);
  }

  /// Builds a URL for endpoints that are consumed directly (stream, coverArt).
  ///
  /// Preserves any base-URL path prefix the user configured — e.g. a Navidrome
  /// instance reverse-proxied at `https://music.example.com/navidrome` keeps
  /// its `/navidrome` segment instead of being silently rewritten to
  /// `https://music.example.com/rest/...`, which used to silently break cover
  /// art and downloads on subpath deployments.
  Uri buildUri(String path, Map<String, dynamic> extraParams) {
    // Each buildUri call gets its own salt (via authParams) so multiple
    // cover-art / stream URIs generated in the same millisecond don't collide.
    final params = <String, dynamic>{
      ...authParams(_username, _password),
      ...extraParams,
    };
    final base = Uri.parse(_baseUrl);
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '$basePath$endpoint',
      queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  /// Builds the Subsonic auth + format query params for [username]/[password].
  /// Used by both [buildUri] and the request interceptor so the salt/token
  /// signing logic lives in exactly one place. Each call generates a fresh salt.
  static Map<String, String> authParams(String username, String password) {
    final salt = _generateSalt();
    return {
      'u': username,
      't': _md5Hash('$password$salt'),
      's': salt,
      'v': ApiConstants.apiVersion,
      'c': ApiConstants.clientName,
      'f': ApiConstants.responseFormat,
    };
  }

  static String _md5Hash(String input) =>
      md5.convert(utf8.encode(input)).toString();
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._username, this._password);

  final String _username;
  final String _password;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.queryParameters
        .addAll(SubsonicClient.authParams(_username, _password));
    handler.next(options);
  }
}

class _SubsonicErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final envelope =
          body['subsonic-response'] as Map<String, dynamic>?;
      if (envelope != null && envelope['status'] == 'failed') {
        final error = envelope['error'] as Map<String, dynamic>?;
        final code = error?['code'] as int? ?? 0;
        final message = error?['message'] as String? ?? 'Unknown error';
        if (code == 40 || code == 41) {
          throw const AuthException();
        }
        throw SubsonicException(message, code: code);
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // HTTP-level auth failures (e.g. a reverse proxy in front of Navidrome
    // demanding Basic auth, or a Subsonic fork returning 401 instead of an
    // envelope `code=40`) must reach the UI as `AuthException` so the setup
    // page can prompt the user to re-enter credentials rather than just
    // saying "network error".
    final status = err.response?.statusCode;
    if (status == 401 || status == 403) {
      handler.reject(DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        error: const AuthException(),
        type: DioExceptionType.badResponse,
      ));
      return;
    }
    handler.reject(DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      error: NetworkException(err.message ?? 'Network error'),
      type: err.type,
    ));
  }
}
