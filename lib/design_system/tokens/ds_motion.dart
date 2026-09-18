import 'package:flutter/animation.dart';

abstract final class DsMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 380);

  static const emphasized = Curves.easeOutCubic;
  static const standard = Curves.easeInOut;
}
