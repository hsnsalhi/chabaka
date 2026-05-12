/// Options de session de jeu — données immutables passées entre /quick-setup
/// et /game/quick (via GoRouter extra) ou construites en dur pour /game/daily.
///
/// Zéro import Flutter — Dart pur.
library;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum GameMode { daily, quick }

enum Difficulty {
  beginner,
  intermediate,
  expert,
  master;

  /// Nom arabe affiché dans l'UI.
  String get labelAr => switch (this) {
        Difficulty.beginner => 'مبتدئ',
        Difficulty.intermediate => 'متوسط',
        Difficulty.expert => 'خبير',
        Difficulty.master => 'أستاذ',
      };

  /// Dimensions de la grille (rows × cols).
  (int rows, int cols) get gridSize => switch (this) {
        Difficulty.beginner => (8, 8),
        Difficulty.intermediate => (9, 13),
        Difficulty.expert => (13, 9),
        Difficulty.master => (13, 13),
      };

  /// Nombre max d'indices autorisés (null = illimité).
  int? get maxHints => switch (this) {
        Difficulty.beginner => null,
        Difficulty.intermediate => 3,
        Difficulty.expert => 1,
        Difficulty.master => 0,
      };

  /// Durée max (null = pas de timer).
  Duration? get timer => switch (this) {
        Difficulty.beginner => null,
        Difficulty.intermediate => const Duration(minutes: 15),
        Difficulty.expert => const Duration(minutes: 10),
        Difficulty.master => const Duration(minutes: 8),
      };

  /// Multiplicateur de score.
  double get scoreMultiplier => switch (this) {
        Difficulty.beginner => 1.0,
        Difficulty.intermediate => 1.5,
        Difficulty.expert => 2.0,
        Difficulty.master => 3.0,
      };

  /// Nombre max de thèmes sélectionnables (null = illimité).
  int? get maxThemes => switch (this) {
        Difficulty.beginner => null,
        Difficulty.intermediate => null,
        Difficulty.expert => 2,
        Difficulty.master => 1,
      };

  /// Sous-titre descriptif affiché dans la carte de sélection.
  String get subtitleAr {
    final (rows, cols) = gridSize;
    final hintStr = maxHints == null
        ? 'تلميحات غير محدودة'
        : (maxHints == 0 ? 'بلا تلميح' : '$maxHints تلميح');
    final timerStr = timer == null
        ? 'بلا توقيت'
        : '${timer!.inMinutes} دقيقة';
    return '$rows×$cols — $hintStr — $timerStr';
  }
}

// ---------------------------------------------------------------------------
// Map traduction catégories
// ---------------------------------------------------------------------------

const kCategoryLabels = <String, String>{
  'common': 'عام',
  'science': 'علوم',
  'food': 'مطبخ',
  'sport': 'رياضة',
  'verb': 'أفعال',
  'adjective': 'صفات',
  'person': 'أعلام',
  'place': 'أماكن',
  'idiom': 'أمثال',
  'art': 'فنون',
  'transport': 'نقل',
  'emotion': 'عواطف',
  'history': 'تاريخ',
  'capital': 'عواصم',
  'body': 'جسم',
  'nature': 'طبيعة',
  'animal': 'حيوانات',
  'plant': 'نباتات',
  'home': 'منزل',
  'country': 'دول',
};

// ---------------------------------------------------------------------------
// GameOptions
// ---------------------------------------------------------------------------

/// Options immuables d'une session de jeu.
///
/// - Pour le mode [GameMode.daily] : utiliser [GameOptions.daily()].
/// - Pour le mode [GameMode.quick] : construire via [GameOptions.quick(...)].
class GameOptions {
  final GameMode mode;
  final Difficulty difficulty;

  /// Catégories filtrées. Vide = tous les thèmes.
  final Set<String> themes;

  const GameOptions._({
    required this.mode,
    required this.difficulty,
    required this.themes,
  });

  /// Constructeur pour le mode quotidien (intermédiaire, tous thèmes, timer off).
  factory GameOptions.daily() => const GameOptions._(
        mode: GameMode.daily,
        difficulty: Difficulty.intermediate,
        themes: {},
      );

  /// Constructeur pour une partie rapide.
  factory GameOptions.quick({
    required Difficulty difficulty,
    Set<String> themes = const {},
  }) =>
      GameOptions._(
        mode: GameMode.quick,
        difficulty: difficulty,
        themes: Set.unmodifiable(themes),
      );

  // ── Helpers dérivés ─────────────────────────────────────────────────────────

  int get rows => difficulty.gridSize.$1;
  int get cols => difficulty.gridSize.$2;

  /// Nombre max d'indices (null = illimité).
  int? get maxHints => difficulty.maxHints;

  /// Timer effectif.
  /// Pour le Daily, pas de timer même si la difficulté en a un normalement.
  Duration? get effectiveTimer =>
      mode == GameMode.daily ? null : difficulty.timer;

  /// Multiplicateur de score.
  double get scoreMultiplier => difficulty.scoreMultiplier;

  /// Catégories à passer au KB (null = pas de filtre SQL).
  Set<String>? get categoriesFilter => themes.isEmpty ? null : themes;

  /// Clé unique pour Hive box scores_quick.
  String get hiveKey {
    final sortedThemes = themes.toList()..sort();
    final themePart = sortedThemes.isEmpty ? 'all' : sortedThemes.join('-');
    return '${difficulty.name}_${themePart}';
  }

  @override
  String toString() =>
      'GameOptions(mode=${mode.name}, difficulty=${difficulty.name}, '
      'themes=${themes.isEmpty ? "all" : themes})';
}
