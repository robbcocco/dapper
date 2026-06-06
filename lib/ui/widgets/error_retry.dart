import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/color_tokens.dart';

/// Shared empty-state widget for "data load failed" cases — full-page error
/// with a friendly message derived from [error] and a Retry button that
/// invokes [onRetry]. Used wherever a Riverpod provider's error branch was
/// previously rendering `Text('$e')`.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  final Object error;
  final FutureOr<void> Function() onRetry;
  /// Smaller layout for inline use (inside dialogs, expanded sections, etc.).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = _classify(error);
    final iconSize = compact ? 28.0 : 40.0;
    final titleSize = compact ? 13.0 : 15.0;
    final detailSize = compact ? 11.0 : 12.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: iconSize,
                color: ColorTokens.textSecondary.withValues(alpha: 0.7)),
            SizedBox(height: compact ? 8 : 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: ColorTokens.textPrimary,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: detailSize,
                  color: ColorTokens.textSecondary,
                ),
              ),
            ],
            SizedBox(height: compact ? 12 : 18),
            FilledButton.tonal(
              onPressed: () => onRetry(),
              style: FilledButton.styleFrom(
                backgroundColor: ColorTokens.surfaceVariant,
                foregroundColor: ColorTokens.textPrimary,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 22,
                  vertical: compact ? 8 : 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Maps the error to an icon + title + optional detail. Detail is `null` for
  /// errors where the title already says everything (avoids "Something went
  /// wrong / Something went wrong" duplication).
  static (IconData, String, String?) _classify(Object error) {
    if (error is AuthException) {
      return (
        Icons.lock_outline,
        'Sign-in failed',
        'Your saved password no longer works. Update it in Settings.'
      );
    }
    if (error is SubsonicException) {
      return (Icons.warning_amber_rounded, 'Server returned an error',
          error.message);
    }
    if (error is NetworkException) {
      return (
        Icons.cloud_off_outlined,
        'Can\'t reach the server',
        'Check your connection or the server URL, then try again.'
      );
    }
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return (
            Icons.cloud_off_outlined,
            'Timed out',
            'The server didn\'t respond in time. Try again or check the server.'
          );
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return (
            Icons.cloud_off_outlined,
            'Can\'t reach the server',
            'Check your connection or the server URL.'
          );
        case DioExceptionType.badResponse:
          final status = error.response?.statusCode;
          if (status == 401 || status == 403) {
            return (
              Icons.lock_outline,
              'Not authorised',
              'Your credentials were rejected by the server.'
            );
          }
          return (Icons.warning_amber_rounded,
              'Server error${status != null ? ' ($status)' : ''}', null);
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
          return (Icons.warning_amber_rounded, 'Request failed', null);
      }
    }
    if (error is TimeoutException) {
      return (
        Icons.cloud_off_outlined,
        'Timed out',
        'The server didn\'t respond in time. Try again or check the server.'
      );
    }
    return (Icons.error_outline, 'Something went wrong', error.toString());
  }
}
