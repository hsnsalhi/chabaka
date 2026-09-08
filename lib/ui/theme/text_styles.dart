import 'package:flutter/material.dart';

import 'chabaka_colors.dart';

/// Styles de texte centralisés.
/// Toutes les tailles respectent les minima RTL arabe (18px body min).
abstract final class ChabakaTextStyles {
  // ── Amiri (titres, accent calligraphique) ───────────────────────────────────

  /// Grand titre d'écran — "شبكة" en splash / home
  static const h1 = TextStyle(
    fontFamily: 'Amiri',
    fontWeight: FontWeight.w700,
    fontSize: 48,
    height: 1.2,
    letterSpacing: 0,
  );

  /// Titre de section
  static const h2 = TextStyle(
    fontFamily: 'Amiri',
    fontWeight: FontWeight.w700,
    fontSize: 32,
    height: 1.25,
  );

  /// Titre de carte / appBar
  static const h3 = TextStyle(
    fontFamily: 'Amiri',
    fontWeight: FontWeight.w700,
    fontSize: 24,
    height: 1.3,
  );

  // ── Cairo (body, labels, UI) ────────────────────────────────────────────────

  /// Corps principal
  static const body = TextStyle(
    fontFamily: 'Cairo',
    fontWeight: FontWeight.w400,
    fontSize: 18,
    height: 1.55,
  );

  /// Corps secondaire (descriptions courtes)
  static const bodySmall = TextStyle(
    fontFamily: 'Cairo',
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.5,
  );

  /// Label bouton principal
  static const labelLarge = TextStyle(
    fontFamily: 'Cairo',
    fontWeight: FontWeight.w700,
    fontSize: 18,
    height: 1.3,
    letterSpacing: 0.2,
  );

  /// Label bouton secondaire / menu item
  static const label = TextStyle(
    fontFamily: 'Cairo',
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.3,
  );

  /// Micro-label (badge, footer)
  static const caption = TextStyle(
    fontFamily: 'Cairo',
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.4,
  );

  // ── Helpers colorés ─────────────────────────────────────────────────────────

  static TextStyle h1Colored(Color color) => h1.copyWith(color: color);
  static TextStyle h2Colored(Color color) => h2.copyWith(color: color);
  static TextStyle h3Colored(Color color) => h3.copyWith(color: color);
  static TextStyle bodyColored(Color color) => body.copyWith(color: color);
  static TextStyle labelLargeColored(Color color) =>
      labelLarge.copyWith(color: color);
  static TextStyle labelColored(Color color) => label.copyWith(color: color);
  static TextStyle captionColored(Color color) =>
      caption.copyWith(color: color);

  /// Style spécial "or" pour splash subtitle
  static TextStyle get splashSubtitle => caption.copyWith(
    color: ChabakaColors.or,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    letterSpacing: 1.5,
  );
}
