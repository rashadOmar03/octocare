import 'package:flutter/material.dart';

/// Shared breakpoints and layout helpers for phones (iOS/Android/Web mobile).
class Responsive {
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isMobile(BuildContext context) => width(context) < 600;

  static bool isCompact(BuildContext context) => width(context) < 400;

  static bool isVeryCompact(BuildContext context) => width(context) < 340;

  static EdgeInsets pagePadding(BuildContext context) {
    final w = width(context);
    return EdgeInsets.fromLTRB(
      w < 360 ? 12 : 16,
      12,
      w < 360 ? 12 : 16,
      16,
    );
  }

  /// Taller tiles on narrow screens so labels are not clipped.
  static double statGridAspectRatio(BuildContext context) {
    if (isVeryCompact(context)) return 0.78;
    if (isCompact(context)) return 0.88;
    if (isMobile(context)) return 0.98;
    return 1.15;
  }

  static SliverGridDelegate statGridDelegate(BuildContext context, {int crossAxisCount = 2}) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      childAspectRatio: statGridAspectRatio(context),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    );
  }

  static double bottomContentPadding(BuildContext context, {bool hasFab = false}) {
    if (!hasFab) return 16;
    return isCompact(context) ? 72 : 88;
  }

  static double navLabelFontSize(BuildContext context) {
    if (isVeryCompact(context)) return 9;
    if (isCompact(context)) return 10;
    return 11;
  }

  static double navIconSize(BuildContext context) {
    if (isCompact(context)) return 22;
    return 24;
  }
}
