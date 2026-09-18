import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Complete, harmonious type scale so no style falls back to the platform
/// default (Roboto). Display/headline use Space Grotesk (caps at w700 — never
/// request a heavier weight or it synthesizes an ugly faux-bold). Titles, body
/// and labels use Plus Jakarta Sans (supports up to w800). Hierarchy is carried
/// mostly by size, not by ever-heavier weights.
TextTheme dsTextTheme(ColorScheme scheme) {
  TextStyle sg({required double size, FontWeight weight = FontWeight.w700, double height = 1.1, double spacing = -0.4}) {
    return GoogleFonts.spaceGrotesk(
      color: scheme.onSurface,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    );
  }

  TextStyle jakarta({
    required double size,
    FontWeight weight = FontWeight.w500,
    double height = 1.4,
    double spacing = 0,
    Color? color,
  }) {
    return GoogleFonts.plusJakartaSans(
      color: color ?? scheme.onSurface,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    );
  }

  return TextTheme(
    displayLarge: sg(size: 44, height: 1.0, spacing: -1.0),
    displayMedium: sg(size: 36, spacing: -0.8),
    displaySmall: sg(size: 30, spacing: -0.6),
    headlineLarge: sg(size: 28, spacing: -0.5),
    headlineMedium: sg(size: 26, spacing: -0.5),
    headlineSmall: sg(size: 22, spacing: -0.4),
    titleLarge: jakarta(size: 20, weight: FontWeight.w800, height: 1.18, spacing: -0.2),
    titleMedium: jakarta(size: 16, weight: FontWeight.w700, height: 1.25),
    titleSmall: jakarta(size: 14, weight: FontWeight.w700, height: 1.3),
    bodyLarge: jakarta(size: 15.5, height: 1.45),
    bodyMedium: jakarta(size: 14, height: 1.45),
    bodySmall: jakarta(size: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
    labelLarge: jakarta(size: 13, weight: FontWeight.w700, spacing: 0.1, color: scheme.onSurfaceVariant),
    labelMedium: jakarta(size: 12, weight: FontWeight.w700, spacing: 0.2, color: scheme.onSurfaceVariant),
    labelSmall: jakarta(size: 11, weight: FontWeight.w600, spacing: 0.3, color: scheme.onSurfaceVariant),
  );
}
