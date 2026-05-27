import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/errors/app_exception.dart';

class SubsonicClient {
  SubsonicClient({
    required String baseUrl,
    required String username,
    required String password,
  }) : _baseUrl = baseUrl,
       _username = username,
       _password = password {
    _dio = Dio(BaseOptions(baseUrl: baseUrl))
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

  /// Builds a URL for endpoints that are consumed directly (stream, coverArt).
  Uri buildUri(String path, Map<String, dynamic> extraParams) {
    final salt = _generateSalt();
    final token = _md5Hash('$_password$salt');
    final params = {
      'u': _username,
      't': token,
      's': salt,
      'v': ApiConstants.apiVersion,
      'c': ApiConstants.clientName,
      'f': ApiConstants.responseFormat,
      ...extraParams,
    };
    return Uri.parse(_baseUrl).replace(
      path: path,
      queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  static String _generateSalt() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  static String _md5Hash(String input) =>
      md5.convert(utf8.encode(input)).toString();
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._username, this._password);

  final String _username;
  final String _password;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final salt = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final token = md5
        .convert(utf8.encode('$_password$salt'))
        .toString();
    options.queryParameters.addAll({
      'u': _username,
      't': token,
      's': salt,
      'v': ApiConstants.apiVersion,
      'c': ApiConstants.clientName,
      'f': ApiConstants.responseFormat,
    });
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
    throw NetworkException(err.message ?? 'Network error');
  }
}
