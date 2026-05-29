import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:dio/dio.dart';

class NavidromeClient {
  NavidromeClient({
    required this.baseUrl,
    required this.username,
    required this.password,
  }) {
    _dio = Dio(BaseOptions(baseUrl: baseUrl));
  }

  final String baseUrl;
  final String username;
  final String password;

  late final Dio _dio;
  String? _token;
  String? _cookieHeader;
  // Gates concurrent first-call logins so two parallel requests don't both
  // POST /auth/login and clobber each other's _token / _cookieHeader.
  Future<void>? _loginInFlight;

  Future<void> _ensureToken() async {
    if (_token != null) return;
    final existing = _loginInFlight;
    if (existing != null) return existing;
    final pending = _login();
    _loginInFlight = pending;
    try {
      await pending;
    } finally {
      if (identical(_loginInFlight, pending)) _loginInFlight = null;
    }
  }

  Future<void> _login() async {
    dev.log('NavidromeClient: logging in as $username at $baseUrl/auth/login');
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
        options: Options(contentType: 'application/json'),
      );
      dev.log('NavidromeClient: login ${res.statusCode}, data: ${res.data}');

      final token = (res.data?['token'] as String?)?.trim();
      if (token == null || token.isEmpty) {
        throw Exception(
            'Login returned ${res.statusCode} but response had no token. '
            'Body: ${res.data}');
      }

      // Capture session cookie — some Navidrome versions validate via cookie.
      String? cookieHeader;
      final cookies = res.headers['set-cookie'];
      if (cookies != null && cookies.isNotEmpty) {
        cookieHeader =
            cookies.map((c) => c.split(';').first.trim()).join('; ');
        dev.log('NavidromeClient: captured cookies: $cookieHeader');
      }

      // Publish token + cookie together so callers never see a half-updated pair.
      _token = token;
      _cookieHeader = cookieHeader;
      dev.log('NavidromeClient: token obtained (${token.length} chars)');
    } on DioException catch (e) {
      final body = e.response?.data;
      throw Exception(
        'Navidrome login failed — '
        'status ${e.response?.statusCode ?? "no response"}, '
        'body: $body',
      );
    }
  }

  Future<Options> _opts({String? contentType}) async {
    await _ensureToken();
    return Options(
      contentType: contentType,
      headers: {
        // Standard Bearer — and Navidrome's own custom header as a fallback.
        'Authorization': 'Bearer $_token',
        'X-Nd-Authorization': 'Bearer $_token',
        ...(_cookieHeader != null ? {'Cookie': _cookieHeader!} : {}),
      },
    );
  }

  Future<T> _call<T>(
    Future<T> Function(Options opts) action, {
    String? contentType,
    required String description,
  }) async {
    try {
      return await action(await _opts(contentType: contentType));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      dev.log('NavidromeClient: $description → $status, body: $body');
      if (status == 401) {
        // Invalidate token and retry once with fresh credentials.
        _token = null;
        _cookieHeader = null;
        try {
          return await action(await _opts(contentType: contentType));
        } on DioException catch (e2) {
          final s = e2.response?.statusCode;
          final b = e2.response?.data;
          throw Exception(
              '$description failed after re-auth — status $s, body: $b');
        }
      }
      throw Exception('$description failed — status $status, body: $body');
    }
  }

  Future<void> updateSong(String id, Map<String, dynamic> fields) =>
      _call<void>(
        (opts) => _dio.patch('/api/song/$id', data: fields, options: opts),
        contentType: 'application/json',
        description: 'PATCH /api/song/$id',
      );

  Future<void> updateAlbumCoverArt(String albumId, Uint8List imageBytes) =>
      _call<void>(
        (opts) => _dio.post(
          '/api/album/$albumId/image',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(imageBytes, filename: 'cover.jpg'),
          }),
          options: opts,
        ),
        description: 'POST /api/album/$albumId/image',
      );
}
