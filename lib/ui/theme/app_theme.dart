import 'package:flutter/material.dart';

import 'colors.dart';

/// Famille principale (texte courant, indices, lettres).
const String _fontBody = 'Cairo';

/// Famille pour titres / accent (AppBar, écrans de feedback).
const String _fontDisplay = 'Amiri';

ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: ChabakaColors.primaryLight,
    onPrimary: ChabakaColors.onPrimaryLight,
    primaryContainer: ChabakaColors.primaryContainerLight,
    onPrimaryContainer: ChabakaColors.onPrimaryContainerLight,
    secondary: ChabakaColors.primaryLight,
    onSecondary: ChabakaColors.onPrimaryLight,
    secondaryContainer: ChabakaColors.secondaryContainerLight,
    onSecondaryContainer: ChabakaColors.onSecondaryContainerLight,
    tertiary: ChabakaColors.primaryLight,
    onTertiary: ChabakaColors.onPrimaryLight,
    error: ChabakaColors.cellErrorFg,
    onError: Colors.white,
    surface: ChabakaColors.surfaceLight,
    onSurface: ChabakaColors.onSurfaceLight,
    surfaceContainerHighest: ChabakaColors.surfaceVariantLight,
    onSurfaceVariant: ChabakaColors.onSurfaceLight,
    outline: ChabakaColors.outlineLight,
    outlineVariant: ChabakaColors.outlineVariantLight,
  );
  return _build(scheme, ChabakaColors.backgroundLight);
}

ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: ChabakaColors.primaryDark,
    onPrimary: ChabakaColors.onPrimaryDark,
    primaryContainer: ChabakaColors.primaryContainerDark,
    onPrimaryContainer: ChabakaColors.onPrimaryContainerDark,
    secondary: ChabakaColors.primaryDark,
    onSecondary: ChabakaColors.onPrimaryDark,
    secondaryContainer: ChabakaColors.secondaryContainerDark,
    onSecondaryContainer: ChabakaColors.onSecondaryContainerDark,
    tertiary: ChabakaColors.primaryDark,
    onTertiary: ChabakaColors.onPrimaryDark,
    error: ChabakaColors.cellErrorFg,
    onError: Colors.white,
    surface: ChabakaColors.surfaceDark,
    onSurface: ChabakaColors.onSurfaceDark,
    surfaceContainerHighest: ChabakaColors.surfaceVariantDark,
    onSurfaceVariant: ChabakaColors.onSurfaceDark,
    outline: ChabakaColors.outlineDark,
    outlineVariant: ChabakaColors.outlineVariantDark,
  );
  return _build(scheme, ChabakaColors.backgroundDark);
}

ThemeData _build(ColorScheme scheme, Color background) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontBody,
    scaffoldBackgroundColor: background,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          displayLarge: _amiri(40, FontWeight.w700, scheme.onSurface),
          displayMedium: _amiri(32, FontWeight.w700, scheme.onSurface),
          displaySmall: _amiri(28, FontWeight.w700, scheme.onSurface),
          headlineLarge: _amiri(28, FontWeight.w700, scheme.onSurface),
          headlineMedium: _amiri(24, FontWeight.w700, scheme.onSurface),
          headlineSmall: _amiri(22, FontWeight.w700, scheme.onSurface),
          titleLarge: _amiri(22, FontWeight.w700, scheme.onSurface),
          titleMedium: _cairo(18, FontWeight.w600, scheme.onSurface),
          titleSmall: _cairo(16, FontWeight.w600, scheme.onSurface),
          bodyLarge: _cairo(18, FontWeight.w400, scheme.onSurface, height: 1.5),
          bodyMedium:
              _cairo(16, FontWeight.w400, scheme.onSurface, height: 1.5),
          bodySmall:
              _cairo(13, FontWeight.w400, scheme.onSurface, height: 1.4),
          labelLarge: _cairo(16, FontWeight.w500, scheme.onSurface),
          labelMedium: _cairo(14, FontWeight.w500, scheme.onSurface),
          labelSmall: _cairo(12, FontWeight.w500, scheme.onSurface),
        )
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: _fontDisplay,
        fontWeight: FontWeight.w700,
        fontSize: 24,
        color: scheme.onPrimary,
        height: 1.3,
      ),
    ),
  );
}

TextStyle _amiri(double size, FontWeight weight, Color color,
        {double? height}) =>
    TextStyle(
      fontFamily: _fontDisplay,
      fontWeight: weight,
      fontSize: size,
      color: color,
      height: height ?? 1.3,
    );

TextStyle _cairo(double size, FontWeight weight, Color color,
        {double? height}) =>
    TextStyle(
      fontFamily: _fontBody,
      fontWeight: weight,
      fontSize: size,
      color: color,
      height: height ?? 1.4,
    );
