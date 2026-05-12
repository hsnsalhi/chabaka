import 'package:flutter/material.dart';

/// Palette officielle Chabaka — Phase A.
///
/// Nomenclature :
///   primary  = bordeaux profond
///   accent   = or impérial
///   surface  = crème / ivoire
///   cc       = brun chaud (Clue-Cell tint)
abstract final class ChabakaColors {
  // ── Core brand ─────────────────────────────────────────────────────────────
  static const bordeaux = Color(0xFF7A1D1D);
  static const bordeauxLight = Color(0xFF9E3333);
  static const bordeauxDark = Color(0xFF5A1010);

  static const or = Color(0xFFD4AF37);
  static const orMuted = Color(0xFFB89430);
  static const orDark = Color(0xFFEFCF60);

  static const creme = Color(0xFFF5E6D3);
  static const cremeDeep = Color(0xFFEAD6BE);
  static const brunChaud = Color(0xFFA8755C);

  // ── Feedback ────────────────────────────────────────────────────────────────
  static const success = Color(0xFF10B981);
  static const successBg = Color(0xFFD1FAE5);
  static const error = Color(0xFFEF4444);
  static const errorBg = Color(0xFFFEE2E2);

  // ── Light palette ───────────────────────────────────────────────────────────
  static const bgLight = Color(0xFFF5E6D3);        // crème ivoire
  static const surfaceLight = Color(0xFFFDF6EE);   // blanc cassé chaud
  static const surfaceVariantLight = Color(0xFFEAD6BE);
  static const onSurfaceLight = Color(0xFF1C0E07);
  static const outlineLight = Color(0xFF8C6E58);
  static const outlineVariantLight = Color(0xFFD4B99A);

  // ── Dark palette ────────────────────────────────────────────────────────────
  static const bgDark = Color(0xFF120C08);
  static const surfaceDark = Color(0xFF1E1510);
  static const surfaceVariantDark = Color(0xFF2C1F17);
  static const onSurfaceDark = Color(0xFFEFDCC8);
  static const outlineDark = Color(0xFF7A5C45);
  static const outlineVariantDark = Color(0xFF3D2B1F);

  // ── Sepia palette ───────────────────────────────────────────────────────────
  static const bgSepia = Color(0xFFF2E0C4);
  static const surfaceSepia = Color(0xFFFAF0DE);
  static const surfaceVariantSepia = Color(0xFFE5D0B0);
  static const onSurfaceSepia = Color(0xFF2A1A0A);
  static const outlineSepia = Color(0xFF9B7B5B);
  static const outlineVariantSepia = Color(0xFFCCAA82);

  // ── Shared ──────────────────────────────────────────────────────────────────
  static const white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);
}
