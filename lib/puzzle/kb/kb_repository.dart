/// Contrat KbRepository — Knowledge Base pour le moteur Chabaka R4.
///
/// Ce fichier définit :
///   - Les data classes ([KbEntry], [KbClue], [LetterConstraint], [KbCategory])
///   - L'interface abstraite [KbRepository] que toute implémentation doit respecter
///   - L'implémentation in-memory [InMemoryKbRepository] pour les tests
///
/// Zéro import Flutter / sqflite — Dart pur.

library;

import 'dart:async';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Catégories thématiques d'une entrée KB.
enum KbCategory {
  common, // vocabulaire courant
  person, // personnalités
  place, // villes / sites géographiques
  country, // pays
  capital, // capitales
  history, // histoire
  science, // sciences
  art, // arts / littérature
  idiom; // idiomes / expressions

  static KbCategory fromString(String s) => KbCategory.values.firstWhere(
    (c) => c.name == s,
    orElse: () => KbCategory.common,
  );
}

/// Type d'indice associé à une entrée.
enum KbClueKind {
  synonym, // synonyme court
  definition, // définition en prose
  idiom, // expression figée
  context; // usage contextuel

  static KbClueKind fromString(String s) => KbClueKind.values.firstWhere(
    (k) => k.name == s,
    orElse: () => KbClueKind.definition,
  );
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Un indice associé à un mot.
class KbClue {
  final String text; // texte de l'indice (arabe ≤ 40 chars idéalement)
  final KbClueKind kind;
  final int priority; // ordre préféré (0 = prioritaire)

  const KbClue({required this.text, required this.kind, this.priority = 0});

  @override
  String toString() => 'KbClue(${kind.name}: "$text")';
}

/// Entrée de la Knowledge Base : un mot avec ses métadonnées et indices.
class KbEntry {
  /// Identifiant unique (correspond à `entries.id` en SQLite).
  final int id;

  /// Forme normalisée R3 (sans diacritiques, ا/أ/إ/آ→ا, ة→ه, ى→ي).
  /// C'est ce que le solver compare aux contraintes.
  final String word;

  /// Forme d'affichage avec hamza, ة, etc.
  final String wordDisplay;

  /// Longueur en graphèmes (= `word.runes.length`).
  final int length;

  final KbCategory category;

  /// Niveau de difficulté 1-3 (V1 : non utilisé par le solver, stocké pour V2).
  final int difficulty;

  final String source; // 'wiktionary', 'wikipedia', 'curated', …

  /// 0 = auto-généré, 1 = audité humain.
  final int reviewed;

  /// Indices associés, triés par priorité croissante.
  final List<KbClue> clues;

  const KbEntry({
    required this.id,
    required this.word,
    required this.wordDisplay,
    required this.length,
    required this.category,
    this.difficulty = 2,
    this.source = 'curated',
    this.reviewed = 0,
    required this.clues,
  });

  /// Indice préféré (priorité la plus basse = meilleur).
  KbClue? get primaryClue => clues.isEmpty
      ? null
      : clues.reduce((a, b) => a.priority <= b.priority ? a : b);

  @override
  String toString() => 'KbEntry($id, "$word", len=$length, ${category.name})';
}

/// Contrainte lettre×position pour une requête solver.
///
/// Exemple : `LetterConstraint(position: 2, letter: 'ع')` signifie
/// "la lettre à l'index 2 (0-based) doit être ع".
class LetterConstraint {
  /// Index 0-based dans le mot.
  final int position;

  /// Lettre arabe normalisée (1 char).
  final String letter;

  const LetterConstraint({required this.position, required this.letter});

  @override
  String toString() => 'LetterConstraint(pos=$position, letter=$letter)';
}

// ---------------------------------------------------------------------------
// Interface abstraite
// ---------------------------------------------------------------------------

/// Contrat que toute implémentation de KB doit respecter.
///
/// L'implémentation principale sera [KbRepositorySqflite] (étape 6).
/// L'implémentation de test est [InMemoryKbRepository].
abstract interface class KbRepository {
  /// Recherche les mots compatibles avec les contraintes données.
  ///
  /// - [length] : longueur exacte du slot à remplir.
  /// - [constraints] : lettres déjà fixées par d'autres slots
  ///   (intersections). Une liste vide = aucune contrainte de lettre.
  /// - [excludeIds] : IDs déjà placés dans la grille (ne pas réutiliser).
  /// - [categories] : si non-null, filtre sur les catégories listées
  ///   (WHERE category IN (...)). Null = pas de filtre.
  /// - [maxDifficulty] : si non-null, ne retourne que les entrées de
  ///   difficulté inférieure ou égale (1 = très connu, 3 = cultivé).
  /// - [limit] : nombre max de résultats (défaut 50 — le solver en prend
  ///   quelques-uns dans un ordre aléatoire seedé).
  ///
  /// Perf cible : < 5 ms en moyenne sur 1 000 appels (implémentation SQLite).
  Future<List<KbEntry>> findMatching({
    required int length,
    List<LetterConstraint> constraints = const [],
    Set<int> excludeIds = const {},
    Set<String>? categories,
    int? maxDifficulty,
    int limit = 50,
  });

  /// Compte le nombre d'entrées compatibles avec un filtre de catégories
  /// (ensemble vide = toutes) et, si donné, un plafond de difficulté.
  /// Utilisé par QuickSetupScreen pour afficher "N mots dispo".
  Future<int> countMatchingCategories(
    Set<String> categories, {
    int? maxDifficulty,
  });

  /// Nombre total d'entrées dans la KB.
  Future<int> countEntries();

  /// Libère les ressources (connexion SQLite, etc.).
  Future<void> close();
}

// ---------------------------------------------------------------------------
// Implémentation in-memory (tests + stub)
// ---------------------------------------------------------------------------

/// Implémentation pure Dart de [KbRepository] pour les tests unitaires.
///
/// Accepte une liste de [KbEntry] directement ; pas de I/O.
/// Perf non critique (scan linéaire, acceptable pour listes < 10 000 entrées
/// en test).
class InMemoryKbRepository implements KbRepository {
  final List<KbEntry> _entries;
  bool _closed = false;

  InMemoryKbRepository(List<KbEntry> entries)
    : _entries = List.unmodifiable(entries);

  @override
  Future<List<KbEntry>> findMatching({
    required int length,
    List<LetterConstraint> constraints = const [],
    Set<int> excludeIds = const {},
    Set<String>? categories,
    int? maxDifficulty,
    int limit = 50,
  }) async {
    _assertOpen();
    final results = <KbEntry>[];
    for (final entry in _entries) {
      if (results.length >= limit) break;
      if (entry.length != length) continue;
      if (excludeIds.contains(entry.id)) continue;
      if (categories != null && !categories.contains(entry.category.name))
        continue;
      if (maxDifficulty != null && entry.difficulty > maxDifficulty) continue;
      if (!_matchesConstraints(entry.word, constraints)) continue;
      results.add(entry);
    }
    return results;
  }

  @override
  Future<int> countMatchingCategories(
    Set<String> categories, {
    int? maxDifficulty,
  }) async {
    _assertOpen();
    return _entries
        .where(
          (e) =>
              (categories.isEmpty || categories.contains(e.category.name)) &&
              (maxDifficulty == null || e.difficulty <= maxDifficulty),
        )
        .length;
  }

  @override
  Future<int> countEntries() async {
    _assertOpen();
    return _entries.length;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  bool _matchesConstraints(String word, List<LetterConstraint> constraints) {
    final runes = word.runes.toList();
    for (final c in constraints) {
      if (c.position < 0 || c.position >= runes.length) return false;
      if (String.fromCharCode(runes[c.position]) != c.letter) return false;
    }
    return true;
  }

  void _assertOpen() {
    if (_closed) throw StateError('KbRepository est fermé');
  }
}
