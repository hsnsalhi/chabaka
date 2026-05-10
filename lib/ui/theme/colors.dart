import 'package:flutter/material.dart';

/// Palette Chabaka — issue de docs/design-spec.md.
class ChabakaColors {
  ChabakaColors._();

  // Light
  static const surfaceLight = Color(0xFFF5EDD8);
  static const surfaceVariantLight = Color(0xFFEAE0C8);
  static const onSurfaceLight = Color(0xFF1C1008);
  static const primaryLight = Color(0xFF8B1A1A);
  static const onPrimaryLight = Color(0xFFFFFFFF);
  static const outlineLight = Color(0xFF6B5E4A);
  static const outlineVariantLight = Color(0xFFC4B49A);
  static const primaryContainerLight = Color(0xFFC84040);
  static const onPrimaryContainerLight = Color(0xFFFFFFFF);
  static const secondaryContainerLight = Color(0xFFF2D5A0);
  static const onSecondaryContainerLight = Color(0xFF1C1008);
  static const backgroundLight = Color(0xFFECDFC0);

  // Dark
  static const surfaceDark = Color(0xFF1E1A14);
  static const surfaceVariantDark = Color(0xFF2C261C);
  static const onSurfaceDark = Color(0xFFEDE0C4);
  static const primaryDark = Color(0xFFD4A04A);
  static const onPrimaryDark = Color(0xFF1C1008);
  static const outlineDark = Color(0xFF7A6B55);
  static const outlineVariantDark = Color(0xFF3D3426);
  static const primaryContainerDark = Color(0xFFB8882A);
  static const onPrimaryContainerDark = Color(0xFF1C1008);
  static const secondaryContainerDark = Color(0xFF342B1A);
  static const onSecondaryContainerDark = Color(0xFFEDE0C4);
  static const backgroundDark = Color(0xFF141008);

  // Feedback (mêmes valeurs light/dark — bordures + fonds très clairs)
  static const cellCorrectFg = Color(0xFF2E7D32);
  static const cellCorrectBg = Color(0xFFE8F5E9);
  static const cellErrorFg = Color(0xFFC62828);
  static const cellErrorBg = Color(0xFFFFEBEE);
}
