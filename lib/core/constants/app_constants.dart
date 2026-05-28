import 'package:flutter/material.dart';

class AppConstants {
  static const Size minWindowSize = Size(1024, 700);
  static const double sidebarWidth = 220;
  static const double artistTreeWidth = 200;
  static const double bottomBarHeight = 72;
  // Extra space below scrollable content so the last item clears the floating bar.
  static const double scrollBottomInset = bottomBarHeight + 16;
  static const double albumCardSize = 180;
  static const int libraryPageSize = 50;
}
