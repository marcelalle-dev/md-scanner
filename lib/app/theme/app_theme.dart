import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';

/// Semantic colours that Material's [ColorScheme] does not cover.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.premium,
    required this.scannerOverlay,
  });

  final Color success;
  final Color warning;
  final Color premium;

  /// Scrim drawn over the camera preview around the detected document.
  final Color scannerOverlay;

  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>()!;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? premium,
    Color? scannerOverlay,
  }) => AppSemanticColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    premium: premium ?? this.premium,
    scannerOverlay: scannerOverlay ?? this.scannerOverlay,
  );

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      premium: Color.lerp(premium, other.premium, t)!,
      scannerOverlay: Color.lerp(scannerOverlay, other.scannerOverlay, t)!,
    );
  }
}

abstract final class AppTheme {
  static const String fontFamily = 'Inter';

  static ThemeData light() => _build(_lightScheme, Brightness.light);

  static ThemeData dark() => _build(_darkScheme, Brightness.dark);

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.electricBlue,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.nightBlue,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFDCE7FF),
        onPrimaryContainer: AppColors.nightBlue,
        secondary: AppColors.electricBlue,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFE3ECFF),
        onSecondaryContainer: const Color(0xFF0A2E7A),
        tertiary: AppColors.electricBlue,
        surface: AppColors.offWhite,
        onSurface: const Color(0xFF10141B),
        onSurfaceVariant: AppColors.neutral600,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: AppColors.neutral100,
        surfaceContainerHigh: AppColors.neutral100,
        surfaceContainerHighest: AppColors.neutral200,
        outline: AppColors.neutral400,
        outlineVariant: AppColors.neutral200,
        error: AppColors.danger,
        onError: Colors.white,
      );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.electricBlue,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppColors.electricBlueSoft,
        onPrimary: AppColors.nightBlue,
        primaryContainer: AppColors.nightBlueSoft,
        onPrimaryContainer: const Color(0xFFDCE7FF),
        secondary: AppColors.electricBlue,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFF12336F),
        onSecondaryContainer: const Color(0xFFDCE7FF),
        tertiary: AppColors.electricBlueSoft,
        surface: AppColors.deepBlack,
        onSurface: const Color(0xFFE9ECF2),
        onSurfaceVariant: AppColors.neutral400,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: AppColors.darkSurface,
        surfaceContainer: AppColors.darkSurface,
        surfaceContainerHigh: AppColors.darkSurfaceHigh,
        surfaceContainerHighest: AppColors.neutral800,
        outline: AppColors.neutral600,
        outlineVariant: AppColors.neutral800,
        error: const Color(0xFFFF8A80),
        onError: const Color(0xFF4A0B0B),
      );

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
    );
    final textTheme = _textTheme(base.textTheme, scheme);

    return base.copyWith(
      textTheme: textTheme,
      extensions: [
        AppSemanticColors(
          success: isDark ? const Color(0xFF58D69A) : AppColors.success,
          warning: isDark ? const Color(0xFFFFC157) : AppColors.warning,
          premium: AppColors.premiumGold,
          scannerOverlay: Colors.black.withValues(alpha: 0.55),
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.control),
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.secondary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.secondary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
        titleTextStyle: textTheme.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.neutral800 : AppColors.nightBlue,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.secondary,
        thumbColor: scheme.secondary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.secondary : null,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    TextStyle? style(TextStyle? source, FontWeight weight, {double? spacing}) =>
        source?.copyWith(
          fontFamily: fontFamily,
          fontWeight: weight,
          letterSpacing: spacing,
          color: scheme.onSurface,
        );

    return base.copyWith(
      displaySmall: style(base.displaySmall, FontWeight.w700, spacing: -0.5),
      headlineLarge: style(base.headlineLarge, FontWeight.w700, spacing: -0.5),
      headlineMedium: style(
        base.headlineMedium,
        FontWeight.w700,
        spacing: -0.3,
      ),
      headlineSmall: style(base.headlineSmall, FontWeight.w600, spacing: -0.2),
      titleLarge: style(base.titleLarge, FontWeight.w600, spacing: -0.2),
      titleMedium: style(base.titleMedium, FontWeight.w600),
      titleSmall: style(base.titleSmall, FontWeight.w600),
      bodyLarge: style(base.bodyLarge, FontWeight.w400),
      bodyMedium: style(base.bodyMedium, FontWeight.w400),
      bodySmall: style(
        base.bodySmall,
        FontWeight.w400,
      )?.copyWith(color: scheme.onSurfaceVariant),
      labelLarge: style(base.labelLarge, FontWeight.w600),
      labelMedium: style(base.labelMedium, FontWeight.w500),
      labelSmall: style(base.labelSmall, FontWeight.w500),
    );
  }
}
