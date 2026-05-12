import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chabaka_colors.dart';

/// Modes de thème supportés par Chabaka.
enum ChabakaThemeMode { light, dark, sepia }

/// Construit le ThemeData pour chaque mode.
abstract final class ChabakaTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        primary: ChabakaColors.bordeaux,
        onPrimary: ChabakaColors.white,
        primaryContainer: ChabakaColors.bordeauxLight,
        onPrimaryContainer: ChabakaColors.white,
        secondary: ChabakaColors.or,
        onSecondary: ChabakaColors.onSurfaceLight,
        secondaryContainer: ChabakaColors.cremeDeep,
        onSecondaryContainer: ChabakaColors.onSurfaceLight,
        tertiary: ChabakaColors.brunChaud,
        onTertiary: ChabakaColors.white,
        error: ChabakaColors.error,
        onError: ChabakaColors.white,
        surface: ChabakaColors.surfaceLight,
        onSurface: ChabakaColors.onSurfaceLight,
        surfaceContainerHighest: ChabakaColors.surfaceVariantLight,
        onSurfaceVariant: ChabakaColors.onSurfaceLight,
        outline: ChabakaColors.outlineLight,
        outlineVariant: ChabakaColors.outlineVariantLight,
        scaffoldBg: ChabakaColors.bgLight,
        statusBarBrightness: Brightness.dark,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        primary: ChabakaColors.orDark,
        onPrimary: ChabakaColors.bgDark,
        primaryContainer: ChabakaColors.orMuted,
        onPrimaryContainer: ChabakaColors.bgDark,
        secondary: ChabakaColors.bordeauxLight,
        onSecondary: ChabakaColors.white,
        secondaryContainer: ChabakaColors.surfaceVariantDark,
        onSecondaryContainer: ChabakaColors.onSurfaceDark,
        tertiary: ChabakaColors.brunChaud,
        onTertiary: ChabakaColors.white,
        error: ChabakaColors.error,
        onError: ChabakaColors.white,
        surface: ChabakaColors.surfaceDark,
        onSurface: ChabakaColors.onSurfaceDark,
        surfaceContainerHighest: ChabakaColors.surfaceVariantDark,
        onSurfaceVariant: ChabakaColors.onSurfaceDark,
        outline: ChabakaColors.outlineDark,
        outlineVariant: ChabakaColors.outlineVariantDark,
        scaffoldBg: ChabakaColors.bgDark,
        statusBarBrightness: Brightness.light,
      );

  /// Sépia : identique au light avec une teinte chaude encore plus forte.
  static ThemeData sepia() => _build(
        brightness: Brightness.light,
        primary: ChabakaColors.bordeaux,
        onPrimary: ChabakaColors.white,
        primaryContainer: ChabakaColors.bordeauxLight,
        onPrimaryContainer: ChabakaColors.white,
        secondary: ChabakaColors.or,
        onSecondary: ChabakaColors.onSurfaceSepia,
        secondaryContainer: ChabakaColors.surfaceVariantSepia,
        onSecondaryContainer: ChabakaColors.onSurfaceSepia,
        tertiary: ChabakaColors.brunChaud,
        onTertiary: ChabakaColors.white,
        error: ChabakaColors.error,
        onError: ChabakaColors.white,
        surface: ChabakaColors.surfaceSepia,
        onSurface: ChabakaColors.onSurfaceSepia,
        surfaceContainerHighest: ChabakaColors.surfaceVariantSepia,
        onSurfaceVariant: ChabakaColors.onSurfaceSepia,
        outline: ChabakaColors.outlineSepia,
        outlineVariant: ChabakaColors.outlineVariantSepia,
        scaffoldBg: ChabakaColors.bgSepia,
        statusBarBrightness: Brightness.dark,
      );

  // ── Builder interne ─────────────────────────────────────────────────────────

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color primaryContainer,
    required Color onPrimaryContainer,
    required Color secondary,
    required Color onSecondary,
    required Color secondaryContainer,
    required Color onSecondaryContainer,
    required Color tertiary,
    required Color onTertiary,
    required Color error,
    required Color onError,
    required Color surface,
    required Color onSurface,
    required Color surfaceContainerHighest,
    required Color onSurfaceVariant,
    required Color outline,
    required Color outlineVariant,
    required Color scaffoldBg,
    required Brightness statusBarBrightness,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      error: error,
      onError: onError,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: scaffoldBg,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: statusBarBrightness,
          statusBarBrightness:
              statusBarBrightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Amiri',
          fontWeight: FontWeight.w700,
          fontSize: 24,
          color: onPrimary,
          height: 1.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outlineVariant, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: outline,
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant,
        thickness: 0.5,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, ColorScheme scheme) {
    return base
        .copyWith(
          displayLarge: _amiri(48, FontWeight.w700, scheme.onSurface, h: 1.2),
          displayMedium: _amiri(40, FontWeight.w700, scheme.onSurface, h: 1.2),
          displaySmall: _amiri(32, FontWeight.w700, scheme.onSurface, h: 1.25),
          headlineLarge: _amiri(28, FontWeight.w700, scheme.onSurface, h: 1.25),
          headlineMedium: _amiri(24, FontWeight.w700, scheme.onSurface, h: 1.3),
          headlineSmall: _amiri(22, FontWeight.w700, scheme.onSurface, h: 1.3),
          titleLarge: _amiri(22, FontWeight.w700, scheme.onSurface, h: 1.3),
          titleMedium: _cairo(18, FontWeight.w600, scheme.onSurface),
          titleSmall: _cairo(16, FontWeight.w600, scheme.onSurface),
          bodyLarge: _cairo(18, FontWeight.w400, scheme.onSurface, h: 1.55),
          bodyMedium: _cairo(16, FontWeight.w400, scheme.onSurface, h: 1.5),
          bodySmall: _cairo(14, FontWeight.w400, scheme.onSurface, h: 1.45),
          labelLarge: _cairo(18, FontWeight.w700, scheme.onSurface),
          labelMedium: _cairo(16, FontWeight.w500, scheme.onSurface),
          labelSmall: _cairo(13, FontWeight.w500, scheme.onSurface),
        )
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
  }

  static TextStyle _amiri(double size, FontWeight weight, Color color,
          {double h = 1.3}) =>
      TextStyle(
          fontFamily: 'Amiri', fontWeight: weight, fontSize: size, color: color, height: h);

  static TextStyle _cairo(double size, FontWeight weight, Color color,
          {double h = 1.4}) =>
      TextStyle(
          fontFamily: 'Cairo', fontWeight: weight, fontSize: size, color: color, height: h);
}
