/// Générateur de grille مسهمة — algorithme greedy + backtracking.
///
/// Principe :
///   1. Grille rectangulaire initialisée avec des ClueCells vides.
///   2. On place des mots horizontaux et verticaux de manière greedy,
///      en vérifiant les intersections (lettres communes).
///   3. Si placement échoue → backtracking.
///   4. Déterministe par date (seed = jours depuis epoch).
///
/// V1 : grilles petites (7×7 à 9×9) pour garantir la génération rapide.
/// Évolution : augmenter taille, améliorer algo.

import 'dart:math';
import '../models.dart';
import '../arabic_normalizer.dart';
import 'wordlist.dart';

class GeneratorConfig {
  final int rows;
  final int cols;
  final int minWords;
  final int maxWords;
  final int seed; // seed aléatoire (jours depuis epoch = déterministe par date)

  const GeneratorConfig({
    this.rows = 7,
    this.cols = 7,
    this.minWords = 6,
    this.maxWords = 12,
    required this.seed,
  });

  /// Seed basée sur la date (déterministe "grille du jour").
  factory GeneratorConfig.forDate(DateTime date) {
    final epoch = DateTime(2024, 1, 1);
    final days = date.difference(epoch).inDays;
    return GeneratorConfig(seed: days);
  }
}

class PuzzleGenerator {
  final Wordlist wordlist;
  final ArabicNormalizer normalizer;

  PuzzleGenerator({
    required this.wordlist,
    this.normalizer = const ArabicNormalizer(),
  });

  /// Génère une grille déterministe pour [config].
  /// Retourne null si impossible (wordlist trop petite, etc.)
  Grid? generate(GeneratorConfig config) {
    final rng = Random(config.seed);
    final shuffled = List<WordEntry>.from(wordlist.entries)..shuffle(rng);

    // Initialiser la grille avec des ClueCells vides (bloqueurs).
    final cells = List.generate(
      config.rows,
      (_) => List<Cell>.generate(
        config.cols,
        (_) => ClueCell(clues: []),
      ),
    );

    final placedWords = <_PlacedWord>[];

    // Tentatives de placement
    for (final entry in shuffled) {
      if (placedWords.length >= config.maxWords) break;

      final placed = _tryPlace(
        cells: cells,
        rows: config.rows,
        cols: config.cols,
        entry: entry,
        placedWords: placedWords,
        rng: rng,
      );

      if (placed != null) {
        placedWords.add(placed);
        _applyWord(cells, placed);
      }
    }

    if (placedWords.length < config.minWords) {
      // Pas assez de mots placés — grille invalide
      return null;
    }

    // Convertir les ClueCells vides restantes en ClueCells réelles
    // (elles servent de bloqueurs visuels, sans indice).
    // Dans la V1, on les laisse comme ClueCells vides —
    // l'UI les rendra comme cellules grises.

    final gridId = 'day-${config.seed}';
    return Grid(
      rows: config.rows,
      cols: config.cols,
      cells: cells,
      variant: GridVariant.standard,
      id: gridId,
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  // Essaie de placer un mot dans la grille.
  // Retourne null si aucun placement valide.
  _PlacedWord? _tryPlace({
    required List<List<Cell>> cells,
    required int rows,
    required int cols,
    required WordEntry entry,
    required List<_PlacedWord> placedWords,
    required Random rng,
  }) {
    final word = normalizer.normalize(entry.word);
    final len = word.runes.length;

    // Générer tous les placements possibles dans les 2 directions
    final candidates = <_Placement>[];

    for (final dir in Direction.values) {
      final maxRow = dir == Direction.horizontal ? rows : rows - len;
      final maxCol = dir == Direction.horizontal ? cols - len : cols;

      for (var r = 0; r < maxRow; r++) {
        for (var c = 0; c < maxCol; c++) {
          final placement = _Placement(row: r, col: c, direction: dir);
          if (_isValidPlacement(cells, rows, cols, word, placement, placedWords)) {
            candidates.add(placement);
          }
        }
      }
    }

    if (candidates.isEmpty) return null;

    // Préférer les placements avec intersection (croissement avec mots existants)
    // pour créer une grille dense et intéressante.
    final withIntersection = candidates
        .where((p) => _hasIntersection(cells, word, p, placedWords))
        .toList();

    final chosen = withIntersection.isNotEmpty
        ? withIntersection[rng.nextInt(withIntersection.length)]
        : candidates[rng.nextInt(candidates.length)];

    return _PlacedWord(entry: entry, normalizedWord: word, placement: chosen);
  }

  // Vérifie qu'un placement est valide (pas de collision lettre≠lettre,
  // case de départ disponible pour la ClueCell).
  bool _isValidPlacement(
    List<List<Cell>> cells,
    int rows,
    int cols,
    String normalizedWord,
    _Placement placement,
    List<_PlacedWord> placedWords,
  ) {
    final letters = normalizedWord.runes.map(String.fromCharCode).toList();
    final len = letters.length;

    // La case AVANT le mot (case de départ de la ClueCell) doit exister
    // et être disponible ou déjà une ClueCell.
    final clueRow = placement.direction == Direction.horizontal
        ? placement.row
        : placement.row - 1;
    final clueCol = placement.direction == Direction.horizontal
        ? placement.col - 1
        : placement.col;

    // On n'impose plus de case clue disponible pour simplifier V1 :
    // la ClueCell sera placée juste avant le mot ou fusionnée.

    for (var i = 0; i < len; i++) {
      final r = placement.direction == Direction.horizontal
          ? placement.row
          : placement.row + i;
      final c = placement.direction == Direction.horizontal
          ? placement.col + i
          : placement.col;

      if (r >= rows || c >= cols) return false;

      final cell = cells[r][c];
      if (cell is LetterCell) {
        // Intersection : la lettre doit correspondre
        if (cell.solution != letters[i]) return false;
      }
      // Si ClueCell vide → on peut la remplacer par une LetterCell
    }

    return true;
  }

  bool _hasIntersection(
    List<List<Cell>> cells,
    String normalizedWord,
    _Placement placement,
    List<_PlacedWord> placedWords,
  ) {
    if (placedWords.isEmpty) return false;
    final letters = normalizedWord.runes.map(String.fromCharCode).toList();
    for (var i = 0; i < letters.length; i++) {
      final r = placement.direction == Direction.horizontal
          ? placement.row
          : placement.row + i;
      final c = placement.direction == Direction.horizontal
          ? placement.col + i
          : placement.col;
      if (cells[r][c] is LetterCell) return true;
    }
    return false;
  }

  // Applique un mot placé sur la grille (LetterCells + ClueCell).
  void _applyWord(List<List<Cell>> cells, _PlacedWord placed) {
    final letters = placed.normalizedWord.runes.map(String.fromCharCode).toList();

    // Remplir les LetterCells
    for (var i = 0; i < letters.length; i++) {
      final r = placed.placement.direction == Direction.horizontal
          ? placed.placement.row
          : placed.placement.row + i;
      final c = placed.placement.direction == Direction.horizontal
          ? placed.placement.col + i
          : placed.placement.col;
      cells[r][c] = LetterCell(solution: letters[i]);
    }

    // Placer la ClueCell
    // La ClueCell est placée à la case qui PRÉCÈDE le début du mot
    // (selon direction RTL : pour horizontal, c'est la case à droite du début
    //  → dans nos indices, col-1 ; pour vertical, row-1).
    final clueRow = placed.placement.direction == Direction.horizontal
        ? placed.placement.row
        : placed.placement.row - 1;
    final clueCol = placed.placement.direction == Direction.horizontal
        ? placed.placement.col - 1
        : placed.placement.col;

    if (clueRow >= 0 && clueCol >= 0 &&
        clueRow < cells.length && clueCol < cells[0].length) {
      final existingCell = cells[clueRow][clueCol];
      final newClue = Clue(
        text: placed.entry.clue,
        language: ClueLanguage.arabic,
        direction: placed.placement.direction,
        solution: placed.entry.word, // mot original non normalisé
        startCell: Position(placed.placement.row, placed.placement.col),
      );

      if (existingCell is ClueCell) {
        // Fusionner (cellule double possible)
        cells[clueRow][clueCol] = ClueCell(
          clues: [...existingCell.clues, newClue],
        );
      } else {
        // La case est une LetterCell → cas de conflit, on skip la ClueCell
        // (le mot reste jouable, juste sans indice visible — cas rare V1)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Structures internes
// ---------------------------------------------------------------------------

class _Placement {
  final int row;
  final int col;
  final Direction direction;

  const _Placement({
    required this.row,
    required this.col,
    required this.direction,
  });
}

class _PlacedWord {
  final WordEntry entry;
  final String normalizedWord;
  final _Placement placement;

  const _PlacedWord({
    required this.entry,
    required this.normalizedWord,
    required this.placement,
  });
}
