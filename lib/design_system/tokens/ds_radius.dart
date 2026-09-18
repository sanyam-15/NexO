import 'package:flutter/widgets.dart';

abstract final class DsRadius {
  static const xs = Radius.circular(8);
  static const sm = Radius.circular(12);
  static const md = Radius.circular(18);
  static const lg = Radius.circular(24);
  static const xl = Radius.circular(30);
  static const full = Radius.circular(999);

  static const brXs = BorderRadius.all(xs);
  static const brSm = BorderRadius.all(sm);
  static const brMd = BorderRadius.all(md);
  static const brLg = BorderRadius.all(lg);
  static const brXl = BorderRadius.all(xl);
  static const brFull = BorderRadius.all(full);
}
