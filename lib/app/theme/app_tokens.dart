import 'package:flutter/material.dart';

/// Brand palette of MD SCANNER.
abstract final class AppColors {
  /// Bleu nuit — main brand colour.
  static const Color nightBlue = Color(0xFF0B1F3A);
  static const Color nightBlueSoft = Color(0xFF16305A);

  /// Bleu électrique — accent used for the primary actions.
  static const Color electricBlue = Color(0xFF1F6BFF);
  static const Color electricBlueSoft = Color(0xFF7FAAFF);

  /// Blanc cassé — light background.
  static const Color offWhite = Color(0xFFF7F8FA);

  /// Gris neutre — secondary surfaces.
  static const Color neutral100 = Color(0xFFEEF0F4);
  static const Color neutral200 = Color(0xFFDDE1E8);
  static const Color neutral400 = Color(0xFF9AA3B2);
  static const Color neutral600 = Color(0xFF5B6575);
  static const Color neutral800 = Color(0xFF2A313D);

  /// Noir profond — dark background.
  static const Color deepBlack = Color(0xFF07090D);
  static const Color darkSurface = Color(0xFF10141B);
  static const Color darkSurfaceHigh = Color(0xFF1A2029);

  static const Color success = Color(0xFF1E9E63);
  static const Color warning = Color(0xFFD98A00);
  static const Color danger = Color(0xFFD23B3B);
  static const Color premiumGold = Color(0xFFE2B33C);
}

/// 4-point spacing scale.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: md,
    vertical: md,
  );
  static const EdgeInsets card = EdgeInsets.all(md);
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius control = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// Width under which layouts switch to their compact variant (small phones).
abstract final class AppBreakpoints {
  static const double compact = 360;
  static const double medium = 600;
}
