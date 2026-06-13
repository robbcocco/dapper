import 'package:flutter/material.dart';

class AppConstants {
  static const Size minWindowSize = Size(1024, 700);
  static const double sidebarWidth = 220;
  static const double artistTreeWidth = 200;
  static const double bottomBarHeight = 72;
  // Extra space below scrollable content so the last item clears the floating bar.
  static const double scrollBottomInset = bottomBarHeight + 16;
  static const double albumCardSize = 180;
  /// Pixel size requested from the server for cover art rendered in bulk-load
  /// grids (albums, genres, artist-detail album list). Smaller than the
  /// displayed widget — the server resize is the long pole during library
  /// scroll, so we trade a touch of crispness for a much faster initial paint.
  static const int gridCoverArtSize = 128;
  static const int libraryPageSize = 50;
}
