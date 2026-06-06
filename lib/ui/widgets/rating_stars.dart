import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/ratings_notifier.dart';
import '../../core/theme/color_tokens.dart';

/// Five-star rating widget. Clicking a star sets the rating to that value;
/// clicking the *current* rating again clears it (set to 0).
///
/// Reads the rating from [RatingsNotifier]'s in-memory map first, falls
/// back to [fallback] so freshly loaded server data shows up before any
/// local edits have been made.
class RatingStars extends ConsumerWidget {
  const RatingStars({
    super.key,
    required this.id,
    this.fallback,
    this.size = 14,
    this.compact = false,
  });

  /// Song / album / artist id passed to Subsonic `setRating`.
  final String id;
  /// Rating returned by the server in the song/album payload — used until
  /// the user has interacted with the stars in this session.
  final int? fallback;
  final double size;
  /// Tighter horizontal padding for use inside dense rows.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(ratingsProvider.select((m) => m[id]));
    final current = overlay ?? fallback ?? 0;
    final notifier = ref.read(ratingsProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          GestureDetector(
            // Clicking the active rating clears it — matches iTunes behaviour.
            onTap: () => notifier.setRating(id, star == current ? 0 : star),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
              child: Icon(
                star <= current ? Icons.star : Icons.star_border,
                size: size,
                color: star <= current
                    ? Colors.amber
                    : ColorTokens.textSecondary.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}
