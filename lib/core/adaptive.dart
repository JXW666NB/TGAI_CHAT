import 'package:flutter/material.dart';

enum ScreenType { phone, tablet, desktop }

class Adaptive {
  static ScreenType of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1200) return ScreenType.desktop;
    if (width >= 600) return ScreenType.tablet;
    return ScreenType.phone;
  }

  static bool isPhone(BuildContext context) => of(context) == ScreenType.phone;
  static bool isTablet(BuildContext context) => of(context) == ScreenType.tablet;
  static bool isDesktop(BuildContext context) => of(context) == ScreenType.desktop;
}
