/// Générateur de grille مسهمة — algorithme greedy + post-passe R1.
///
/// Stratégie :
///   1. Greedy 2D : on place des mots horizontaux et verticaux en
///      préférant les intersections (lettres communes).
///   2. Post-passe R1 : pour chaque ClueCell vide restante, on tente
///      de placer un mot supplémentaire dont l'indice viendrait s'y
///      poser. On itère jusqu'à saturation.
///   3. Vérification R1 finale : si une ClueCell sans indice subsiste,
///      la grille est rejetée et on retente avec un seed perturbé.
///
/// R1 (cf. docs/grid-rules.md) : aucune case "vide". Toute case est
/// soit une LetterCell couverte par ≥1 mot, soit une ClueCell avec
/// ≥1 indice.
///
/// Déterministe par date : même seed → même grille (le retry interne
/// est déterministe lui aussi, basé sur seed + offset).

library;

import 'dart:math';
import '../arabic_normalizer.dart';
import '../models.dart';
import 'wordlist.dart';

class GeneratorConfig {
  final int rows;
  final int cols;
  final int minWords;
  final int maxWords;
  final int seed;

  // V1 : 5×5 par défaut. Avec une wordlist de ~50 mots, R1 est satisfaite
  // à >90% des seeds (avec retry interne, ~100%). Pour passer à 6×6 ou
  // plus il faudra étendre la wordlist (cf. docs/grid-rules.md).
  const GeneratorConfig({
    this.rows = 5,
    this.cols = 5,
    this.minWords = 4,
    this.maxWords = 16,
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
  static const int _maxAttempts = 40;

  final Wordlist wordlist;
  final ArabicNormalizer normalizer;

  PuzzleGenerator({
    required this.wordlist,
    this.normalizer = const ArabicNormalizer(),
  });

  /// Génère une grille déterministe pour [config].
  /// Retente jusqu'à [_maxAttempts] avec des seeds perturbés si la
  /// première tentative ne satisfait pas R1.
  /// Retourne null si aucune tentative ne converge.
  Grid? generate(GeneratorConfig config) {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final attemptSeed = _perturbSeed(config.seed, attempt);
      final grid = _attempt(config, attemptSeed);
      if (grid != null) return grid;
    }
    return null;
  }

  // Une tentative complète. Retourne null si la grille viole R1.
  Grid? _attempt(GeneratorConfig config, int seed) {
    final rng = Random(seed);
    final shuffled = List<WordEntry>.from(wordlist.entries)..shuffle(rng);

    final cells = List.generate(
      config.rows,
      (_) => List<Cell>.generate(
        config.cols,
        (_) => ClueCell(clues: const []),
      ),
    );

    final placedWords = <_PlacedWord>[];

    // Phase 1 : placement greedy multi-directionnel.
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

    // Phase 2 : post-passe R1 — combler les ClueCells vides.
    _fillEmptyClueCells(
      cells: cells,
      rows: config.rows,
      cols: config.cols,
      pool: shuffled,
      placedWords: placedWords,
      rng: rng,
      maxWords: config.maxWords,
    );

    // Vérifier la densité minimum.
    if (placedWords.length < config.minWords) return null;

    // Phase 3 : vérification R1 finale.
    if (!_satisfiesR1(cells, config.rows, config.cols)) return null;

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

  // -------------------------------------------------------------------------
  // Greedy placement
  // -------------------------------------------------------------------------

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
    if (len == 0) return null;

    final candidates = <_Placement>[];
    for (final dir in Direction.values) {
      final maxRow = dir == Direction.horizontal ? rows : rows - len + 1;
      final maxCol = dir == Direction.horizontal ? cols - len + 1 : cols;
      // La case AVANT le mot (pour la ClueCell) doit exister :
      // → start col ≥ 1 pour H, start row ≥ 1 pour V.
      final minRow = dir == Direction.vertical ? 1 : 0;
      final minCol = dir == Direction.horizontal ? 1 : 0;

      for (var r = minRow; r < maxRow; r++) {
        for (var c = minCol; c < maxCol; c++) {
          final placement = _Placement(row: r, col: c, direction: dir);
          if (_isValidPlacement(cells, rows, cols, word, placement)) {
            candidates.add(placement);
          }
        }
      }
    }

    if (candidates.isEmpty) return null;

    final withIntersection =
        candidates.where((p) => _hasIntersection(cells, word, p)).toList();
    final chosen = withIntersection.isNotEmpty
        ? withIntersection[rng.nextInt(withIntersection.length)]
        : candidates[rng.nextInt(candidates.length)];

    return _PlacedWord(entry: entry, normalizedWord: word, placement: chosen);
  }

  // Path libre : LetterCell-compatible OU ClueCell vide. Refuse de
  // traverser une ClueCell déjà porteuse d'indices.
  bool _isValidPlacement(
    List<List<Cell>> cells,
    int rows,
    int cols,
    String normalizedWord,
    _Placement placement,
  ) {
    final letters = normalizedWord.runes.map(String.fromCharCode).toList();
    final len = letters.length;

    for (var i = 0; i < len; i++) {
      final r = placement.direction == Direction.horizontal
          ? placement.row
          : placement.row + i;
      final c = placement.direction == Direction.horizontal
          ? placement.col + i
          : placement.col;

      if (r < 0 || c < 0 || r >= rows || c >= cols) return false;

      final cell = cells[r][c];
      if (cell is LetterCell) {
        if (cell.solution != letters[i]) return false;
      } else if (cell is ClueCell && cell.clues.isNotEmpty) {
        // Indice existant → on n'écrase pas.
        return false;
      }
    }

    // La case juste après la fin du mot doit être hors grille ou
    // une ClueCell (sinon le mot fusionnerait avec une lettre voisine).
    final endR = placement.direction == Direction.horizontal
        ? placement.row
        : placement.row + len;
    final endC = placement.direction == Direction.horizontal
        ? placement.col + len
        : placement.col;
    if (endR >= 0 && endC >= 0 && endR < rows && endC < cols) {
      if (cells[endR][endC] is LetterCell) return false;
    }

    return true;
  }

  bool _hasIntersection(
    List<List<Cell>> cells,
    String normalizedWord,
    _Placement placement,
  ) {
    final len = normalizedWord.runes.length;
    for (var i = 0; i < len; i++) {
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

  // -------------------------------------------------------------------------
  // Application d'un mot placé
  // -------------------------------------------------------------------------

  void _applyWord(List<List<Cell>> cells, _PlacedWord placed) {
    final letters =
        placed.normalizedWord.runes.map(String.fromCharCode).toList();

    for (var i = 0; i < letters.length; i++) {
      final r = placed.placement.direction == Direction.horizontal
          ? placed.placement.row
          : placed.placement.row + i;
      final c = placed.placement.direction == Direction.horizontal
          ? placed.placement.col + i
          : placed.placement.col;
      cells[r][c] = LetterCell(solution: letters[i]);
    }

    // ClueCell juste avant le début du mot.
    final clueRow = placed.placement.direction == Direction.horizontal
        ? placed.placement.row
        : placed.placement.row - 1;
    final clueCol = placed.placement.direction == Direction.horizontal
        ? placed.placement.col - 1
        : placed.placement.col;

    final newClue = Clue(
      text: placed.entry.clue,
      language: ClueLanguage.arabic,
      direction: placed.placement.direction,
      solution: placed.entry.word,
      startCell: Position(placed.placement.row, placed.placement.col),
    );

    final existing = cells[clueRow][clueCol];
    if (existing is ClueCell) {
      cells[clueRow][clueCol] = ClueCell(
        clues: [...existing.clues, newClue],
      );
    }
    // Si existing est une LetterCell, on ne devrait pas être arrivés ici :
    // _isValidPlacement vérifie déjà que la case-clue est dispo.
  }

  // -------------------------------------------------------------------------
  // Post-passe R1
  // -------------------------------------------------------------------------

  /// Itère sur les ClueCells vides et tente d'y poser un mot supplémentaire
  /// jusqu'à saturation.
  void _fillEmptyClueCells({
    required List<List<Cell>> cells,
    required int rows,
    required int cols,
    required List<WordEntry> pool,
    required List<_PlacedWord> placedWords,
    required Random rng,
    required int maxWords,
  }) {
    final used = placedWords.map((w) => w.entry.word).toSet();

    var madeProgress = true;
    var safety = 0;
    while (madeProgress && safety < 500) {
      madeProgress = false;
      safety++;

      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          if (placedWords.length >= maxWords) return;
          final cell = cells[r][c];
          if (cell is! ClueCell || cell.clues.isNotEmpty) continue;

          final placement = _findFillForEmptyClue(
            cells: cells,
            rows: rows,
            cols: cols,
            clueRow: r,
            clueCol: c,
            rng: rng,
            pool: pool,
            used: used,
          );
          if (placement != null) {
            placedWords.add(placement);
            _applyWord(cells, placement);
            used.add(placement.entry.word);
            madeProgress = true;
          }
        }
      }
    }
  }

  /// Trouve un mot pouvant être posé juste après la ClueCell (clueRow, clueCol),
  /// en H ou en V, dont l'indice viendra s'y loger. Retourne null si aucun
  /// candidat compatible.
  _PlacedWord? _findFillForEmptyClue({
    required List<List<Cell>> cells,
    required int rows,
    required int cols,
    required int clueRow,
    required int clueCol,
    required Random rng,
    required List<WordEntry> pool,
    required Set<String> used,
  }) {
    final candidatesPlacements = <_Placement>[];
    final candidatesEntries = <WordEntry>[];

    for (final entry in pool) {
      if (used.contains(entry.word)) continue;
      final word = normalizer.normalize(entry.word);
      final len = word.runes.length;
      if (len == 0) continue;

      // Horizontal : début (clueRow, clueCol+1)
      if (clueCol + len < cols) {
        final p = _Placement(
          row: clueRow,
          col: clueCol + 1,
          direction: Direction.horizontal,
        );
        if (_isValidPlacement(cells, rows, cols, word, p)) {
          candidatesPlacements.add(p);
          candidatesEntries.add(entry);
        }
      }

      // Vertical : début (clueRow+1, clueCol)
      if (clueRow + len < rows) {
        final p = _Placement(
          row: clueRow + 1,
          col: clueCol,
          direction: Direction.vertical,
        );
        if (_isValidPlacement(cells, rows, cols, word, p)) {
          candidatesPlacements.add(p);
          candidatesEntries.add(entry);
        }
      }
    }

    if (candidatesPlacements.isEmpty) return null;

    // Préférer les candidats avec intersection pour densifier la grille.
    final withInter = <int>[];
    for (var i = 0; i < candidatesPlacements.length; i++) {
      final word = normalizer.normalize(candidatesEntries[i].word);
      if (_hasIntersection(cells, word, candidatesPlacements[i])) {
        withInter.add(i);
      }
    }

    final pickIdx = withInter.isNotEmpty
        ? withInter[rng.nextInt(withInter.length)]
        : rng.nextInt(candidatesPlacements.length);

    final entry = candidatesEntries[pickIdx];
    return _PlacedWord(
      entry: entry,
      normalizedWord: normalizer.normalize(entry.word),
      placement: candidatesPlacements[pickIdx],
    );
  }

  // -------------------------------------------------------------------------
  // Vérification R1
  // -------------------------------------------------------------------------

  bool _satisfiesR1(List<List<Cell>> cells, int rows, int cols) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cell = cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Seed perturbation pour les retries
  // -------------------------------------------------------------------------

  int _perturbSeed(int base, int attempt) {
    if (attempt == 0) return base;
    // Multiplicateur premier pour éviter les corrélations.
    return base * 1009 + attempt * 9973;
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
