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

  Future<String> _getToken() async {
    if (_token != null) return _token!;
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': username, 'password': password},
      options: Options(contentType: 'application/json'),
    );
    _token = response.data!['token'] as String;
    return _token!;
  }

  Future<void> updateSong(String id, Map<String, dynamic> fields) async {
    final token = await _getToken();
    await _dio.put<void>(
      '/api/song/$id',
      data: fields,
      options: Options(
        contentType: 'application/json',
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }
}
