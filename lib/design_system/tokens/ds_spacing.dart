import 'package:flutter/widgets.dart';

abstract final class DsSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class DsInsets {
  static const page = EdgeInsets.symmetric(horizontal: DsSpacing.md);
  static const card = EdgeInsets.all(DsSpacing.md);
}
