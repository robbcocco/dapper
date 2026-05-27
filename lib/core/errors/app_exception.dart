sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;
}

final class NetworkException extends AppException {
  const NetworkException(super.message);
}

final class SubsonicException extends AppException {
  const SubsonicException(super.message, {required this.code});
  final int code;
}

final class AuthException extends AppException {
  const AuthException() : super('Invalid credentials');
}

final class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

final class StorageException extends AppException {
  const StorageException(super.message);
}
