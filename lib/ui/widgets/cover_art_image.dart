import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../application/providers/providers.dart';
import '../../core/theme/color_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoverArtImage extends ConsumerWidget {
  const CoverArtImage({
    super.key,
    required this.coverArtId,
    this.size = 256,
    this.borderRadius = 4,
  });

  final String? coverArtId;
  final int size;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (coverArtId == null) return _placeholder();

    final repo = ref.watch(libraryRepositoryProvider);
    if (repo == null) return _placeholder();

    final serverId = ref.watch(selectedServerProvider)?.id ?? '';
    final uri = repo.coverArtUri(coverArtId!, size: size);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: uri.toString(),
        cacheKey: 'ca_${serverId}_${coverArtId}_$size',
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (ctx, url) => _placeholder(),
        errorWidget: (ctx, url, err) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() => ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: ColorTokens.surfaceVariant,
          child: const Icon(Icons.album, color: ColorTokens.textSecondary),
        ),
      );
}
