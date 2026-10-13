import 'package:flutter/material.dart';

import 'chabaka_colors.dart';

/// Palettes de couleurs proposées dans les réglages (« الألوان »).
///
/// Chaque palette fournit la couleur de marque (primaire), l'accent et les
/// surfaces des modes clair et sombre. Le mode sépia réutilise les surfaces
/// sépia communes avec la marque de la palette.
enum ChabakaPalette {
  classic(
    labelAr: 'كلاسيكي',
    primary: Color(0xFF7A1D1D),
    primaryLight: Color(0xFF9E3333),
    primaryDark: Color(0xFF5A1010),
    accent: Color(0xFFD4AF37),
    accentMuted: Color(0xFFB89430),
    accentBright: Color(0xFFEFCF60),
    tertiary: Color(0xFFA8755C),
    bgLight: Color(0xFFF5E6D3),
    surfaceLight: Color(0xFFFDF6EE),
    surfaceVariantLight: Color(0xFFEAD6BE),
    onSurfaceLight: Color(0xFF1C0E07),
    outlineLight: Color(0xFF8C6E58),
    outlineVariantLight: Color(0xFFD4B99A),
    bgDark: Color(0xFF120C08),
    surfaceDark: Color(0xFF1E1510),
    surfaceVariantDark: Color(0xFF2C1F17),
    onSurfaceDark: Color(0xFFEFDCC8),
    outlineDark: Color(0xFF7A5C45),
    outlineVariantDark: Color(0xFF3D2B1F),
  ),
  lagune(
    labelAr: 'زمردي',
    primary: Color(0xFF0F6E56),
    primaryLight: Color(0xFF1E8A6E),
    primaryDark: Color(0xFF0A4F3E),
    accent: Color(0xFFD98A2B),
    accentMuted: Color(0xFFB8731F),
    accentBright: Color(0xFFF2A94A),
    tertiary: Color(0xFF5F7268),
    bgLight: Color(0xFFF4F1EA),
    surfaceLight: Color(0xFFFFFFFF),
    surfaceVariantLight: Color(0xFFE6EFE9),
    onSurfaceLight: Color(0xFF13201A),
    outlineLight: Color(0xFF6E8278),
    outlineVariantLight: Color(0xFFC7D3CB),
    bgDark: Color(0xFF0B1512),
    surfaceDark: Color(0xFF13201B),
    surfaceVariantDark: Color(0xFF1C2E27),
    onSurfaceDark: Color(0xFFDCE8E1),
    outlineDark: Color(0xFF4F6A5E),
    outlineVariantDark: Color(0xFF27392F),
  ),
  nuit(
    labelAr: 'ليلي',
    primary: Color(0xFF1E3A8A),
    primaryLight: Color(0xFF2F52B8),
    primaryDark: Color(0xFF132559),
    accent: Color(0xFFF59E0B),
    accentMuted: Color(0xFFC97F08),
    accentBright: Color(0xFFFBBF3F),
    tertiary: Color(0xFF5B6880),
    bgLight: Color(0xFFF2F4F8),
    surfaceLight: Color(0xFFFFFFFF),
    surfaceVariantLight: Color(0xFFE3E8F2),
    onSurfaceLight: Color(0xFF0F1A2E),
    outlineLight: Color(0xFF6B7890),
    outlineVariantLight: Color(0xFFC5CCDA),
    bgDark: Color(0xFF0A0F1E),
    surfaceDark: Color(0xFF121A30),
    surfaceVariantDark: Color(0xFF1C2742),
    onSurfaceDark: Color(0xFFDDE3F2),
    outlineDark: Color(0xFF4C5A7A),
    outlineVariantDark: Color(0xFF273352),
  ),
  safran(
    labelAr: 'زعفراني',
    primary: Color(0xFFC2410C),
    primaryLight: Color(0xFFE05A24),
    primaryDark: Color(0xFF8F2E07),
    accent: Color(0xFFE0A526),
    accentMuted: Color(0xFFBC8A1C),
    accentBright: Color(0xFFF3BE4A),
    tertiary: Color(0xFF8A6A4F),
    bgLight: Color(0xFFFBF3E8),
    surfaceLight: Color(0xFFFFFCF7),
    surfaceVariantLight: Color(0xFFF5E3CC),
    onSurfaceLight: Color(0xFF2B1A10),
    outlineLight: Color(0xFF8A6A4F),
    outlineVariantLight: Color(0xFFDCC4A6),
    bgDark: Color(0xFF170E08),
    surfaceDark: Color(0xFF221610),
    surfaceVariantDark: Color(0xFF33221A),
    onSurfaceDark: Color(0xFFF0DFCE),
    outlineDark: Color(0xFF7A5A45),
    outlineVariantDark: Color(0xFF3F2B20),
  ),
  indigo(
    labelAr: 'نيلي',
    primary: Color(0xFF4F39B8),
    primaryLight: Color(0xFF6A52D9),
    primaryDark: Color(0xFF372683),
    accent: Color(0xFF14B8A6),
    accentMuted: Color(0xFF0E9385),
    accentBright: Color(0xFF2DD4BF),
    tertiary: Color(0xFF7A7299),
    bgLight: Color(0xFFF4F2FA),
    surfaceLight: Color(0xFFFFFFFF),
    surfaceVariantLight: Color(0xFFE9E5F6),
    onSurfaceLight: Color(0xFF17122B),
    outlineLight: Color(0xFF7A7299),
    outlineVariantLight: Color(0xFFCDC6E3),
    bgDark: Color(0xFF0F0C1E),
    surfaceDark: Color(0xFF181430),
    surfaceVariantDark: Color(0xFF241E45),
    onSurfaceDark: Color(0xFFE4DFF5),
    outlineDark: Color(0xFF574E80),
    outlineVariantDark: Color(0xFF2F284F),
  );

  const ChabakaPalette({
    required this.labelAr,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.accentMuted,
    required this.accentBright,
    required this.tertiary,
    required this.bgLight,
    required this.surfaceLight,
    required this.surfaceVariantLight,
    required this.onSurfaceLight,
    required this.outlineLight,
    required this.outlineVariantLight,
    required this.bgDark,
    required this.surfaceDark,
    required this.surfaceVariantDark,
    required this.onSurfaceDark,
    required this.outlineDark,
    required this.outlineVariantDark,
  });

  final String labelAr;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color accentMuted;

  /// Version lumineuse de l'accent, utilisée comme primaire en mode sombre.
  final Color accentBright;
  final Color tertiary;

  final Color bgLight;
  final Color surfaceLight;
  final Color surfaceVariantLight;
  final Color onSurfaceLight;
  final Color outlineLight;
  final Color outlineVariantLight;

  final Color bgDark;
  final Color surfaceDark;
  final Color surfaceVariantDark;
  final Color onSurfaceDark;
  final Color outlineDark;
  final Color outlineVariantDark;

  static ChabakaPalette fromName(String? name) => values.firstWhere(
    (p) => p.name == name,
    orElse: () => ChabakaPalette.classic,
  );
}

/// Couleurs de marque de la palette active, exposées via le [ThemeData]
/// (`Theme.of(context).extension<ChabakaBrand>()` ou `context.brand`).
///
/// Elles ne dépendent pas du mode clair/sombre : ce sont les couleurs
/// « signature » (titres, icônes, dégradés) qui restent identiques d'un mode
/// à l'autre, comme le bordeaux et l'or de la palette classique.
class ChabakaBrand extends ThemeExtension<ChabakaBrand> {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color accentMuted;
  final Color tertiary;

  const ChabakaBrand({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.accentMuted,
    required this.tertiary,
  });

  factory ChabakaBrand.of(ChabakaPalette p) => ChabakaBrand(
    primary: p.primary,
    primaryLight: p.primaryLight,
    primaryDark: p.primaryDark,
    accent: p.accent,
    accentMuted: p.accentMuted,
    tertiary: p.tertiary,
  );

  /// Palette classique, utilisée si un widget est affiché hors d'un thème
  /// Chabaka (tests, aperçus).
  static const ChabakaBrand classic = ChabakaBrand(
    primary: ChabakaColors.bordeaux,
    primaryLight: ChabakaColors.bordeauxLight,
    primaryDark: ChabakaColors.bordeauxDark,
    accent: ChabakaColors.or,
    accentMuted: ChabakaColors.orMuted,
    tertiary: ChabakaColors.brunChaud,
  );

  @override
  ChabakaBrand copyWith({
    Color? primary,
    Color? primaryLight,
    Color? primaryDark,
    Color? accent,
    Color? accentMuted,
    Color? tertiary,
  }) => ChabakaBrand(
    primary: primary ?? this.primary,
    primaryLight: primaryLight ?? this.primaryLight,
    primaryDark: primaryDark ?? this.primaryDark,
    accent: accent ?? this.accent,
    accentMuted: accentMuted ?? this.accentMuted,
    tertiary: tertiary ?? this.tertiary,
  );

  @override
  ChabakaBrand lerp(ThemeExtension<ChabakaBrand>? other, double t) {
    if (other is! ChabakaBrand) return this;
    return ChabakaBrand(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
    );
  }
}

extension ChabakaBrandContext on BuildContext {
  /// Couleurs de marque de la palette active.
  ChabakaBrand get brand =>
      Theme.of(this).extension<ChabakaBrand>() ?? ChabakaBrand.classic;
}
