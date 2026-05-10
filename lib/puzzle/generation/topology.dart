/// Moteur R4 — Topology-First Slot-Filling Backtracking.
///
/// Garantit :
///   R1 : toute ClueCell a ≥ 1 indice.
///   R4 : aucune run accidentelle (toutes les LetterCells sont dans un slot).
///
/// Stratégie (§ 3.2 spec R4) :
///   PHASE A — Sélection d'un patron de grille pré-validé (isomorphe à une
///             vraie grille مسهمة) selon le seed.
///   PHASE B — Backtracking slot par slot avec requêtes KB.
///   PHASE C — Attribution des clues + construction Grid.
///
/// Les patrons sont des masques binaires (C=ClueCell, .=LetterCell) garantis :
///   - toute ClueCell précède au moins un slot H ou V (R1),
///   - toutes les LetterCells sont dans un slot (R4),
///   - aucun slot de longueur 1.

library;

import 'dart:math';
import '../models.dart';
import '../kb/kb_repository.dart';

// ---------------------------------------------------------------------------
// Slot
// ---------------------------------------------------------------------------

class Slot {
  final Direction direction;
  final int startRow;
  final int startCol;
  final int length;

  const Slot({
    required this.direction,
    required this.startRow,
    required this.startCol,
    required this.length,
  });

  List<(int row, int col)> get positions => List.generate(length, (i) {
        return direction == Direction.horizontal
            ? (startRow, startCol + i)
            : (startRow + i, startCol);
      });

  (int row, int col) get clueCellPos {
    return direction == Direction.horizontal
        ? (startRow, startCol - 1)
        : (startRow - 1, startCol);
  }

  @override
  String toString() =>
      'Slot(${direction.name} ($startRow,$startCol) len=$length)';
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class TopologyConfig {
  final int rows;
  final int cols;
  final int seed;

  /// Probabilité que la topologie soit générée dynamiquement (vs patron fixe).
  /// Pour V1, toujours 0 (patrons fixes). En V2 on peut explorer la génération.
  final double splitProb;

  final int backtrackTimeoutMs;
  final int maxRetries;

  const TopologyConfig({
    required this.rows,
    required this.cols,
    required this.seed,
    this.splitProb = 0.35,
    this.backtrackTimeoutMs = 2000,
    this.maxRetries = 40,
  });

  factory TopologyConfig.forDate(DateTime date, {int rows = 7, int cols = 7}) {
    final epoch = DateTime(2024, 1, 1);
    final days = date.difference(epoch).inDays;
    return TopologyConfig(rows: rows, cols: cols, seed: days);
  }
}

// ---------------------------------------------------------------------------
// Patrons pré-validés (masques isClue)
// ---------------------------------------------------------------------------

/// Représente un patron de grille : liste de booléens (true=ClueCell) dans
/// l'ordre ligne par ligne, gauche→droite.
class _Pattern {
  final int rows;
  final int cols;
  final List<bool> mask; // length = rows*cols

  const _Pattern({required this.rows, required this.cols, required this.mask});

  bool isClue(int r, int c) => mask[r * cols + c];

  List<List<bool>> toGrid() {
    return List.generate(
      rows,
      (r) => List.generate(cols, (c) => isClue(r, c)),
    );
  }
}

// Patrons pré-validés par force brute (R1 + R4 strict).
// Contrainte : tout run de LetterCells délimité par bords ou ClueCells a longueur >= 2.
// Toute ClueCell commence exactement un slot H ou V de longueur >= 2.
// Générés par scripts/generate_patterns.dart.
const _patterns5x5 = [
  // Patron 0 (lens=[2, 2, 2, 2, 3, 4, 4])
  // C.... / C.... / CC... / ..C.. / ..C..
  _Pattern(rows: 5, cols: 5, mask: [
    true,  false, false, false, false, // C....
    true,  false, false, false, false, // C....
    true,  true,  false, false, false, // CC...
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
  ]),
  // Patron 1 (lens=[2, 2, 2, 2, 2, 4, 4, 4])
  // CCC.. / ..C.. / ..C.. / C.... / C....
  _Pattern(rows: 5, cols: 5, mask: [
    true,  true,  true,  false, false, // CCC..
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
    true,  false, false, false, false, // C....
    true,  false, false, false, false, // C....
  ]),
  // Patron 2 (lens=[2, 2, 2, 2, 2, 4, 4])
  // CCC.. / ..C.. / ..C.. / ..C.. / ..C..
  _Pattern(rows: 5, cols: 5, mask: [
    true,  true,  true,  false, false, // CCC..
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
  ]),
  // Patron 3 (lens=[2, 2, 2, 2, 3, 3, 4, 4])
  // CCC.. / ..C.. / ...CC / ..... / C....
  _Pattern(rows: 5, cols: 5, mask: [
    true,  true,  true,  false, false, // CCC..
    false, false, true,  false, false, // ..C..
    false, false, false, true,  true,  // ...CC
    false, false, false, false, false, // .....
    true,  false, false, false, false, // C....
  ]),
  // Patron 4 (lens=[2, 2, 2, 2, 2, 2, 4, 4])
  // CCC.. / ..C.. / ...CC / ..... / ..C..
  _Pattern(rows: 5, cols: 5, mask: [
    true,  true,  true,  false, false, // CCC..
    false, false, true,  false, false, // ..C..
    false, false, false, true,  true,  // ...CC
    false, false, false, false, false, // .....
    false, false, true,  false, false, // ..C..
  ]),
  // Patron 5 (lens=[2, 4, 4, 4, 4, 4, 4])
  // C..CC / C.... / C.... / C.... / C....
  _Pattern(rows: 5, cols: 5, mask: [
    true,  false, false, true,  true,  // C..CC
    true,  false, false, false, false, // C....
    true,  false, false, false, false, // C....
    true,  false, false, false, false, // C....
    true,  false, false, false, false, // C....
  ]),
  // Patron 6 (lens=[2, 2, 2, 2, 3, 3, 4, 4])
  // C...C / C.... / CC... / ..C.. / ..C..
  _Pattern(rows: 5, cols: 5, mask: [
    true,  false, false, false, true,  // C...C
    true,  false, false, false, false, // C....
    true,  true,  false, false, false, // CC...
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
  ]),
  // Patron 7 (lens=[2, 2, 2, 2, 2, 4, 4])
  // C.... / C.... / CCC.. / ..C.. / ..C..
  _Pattern(rows: 5, cols: 5, mask: [
    true,  false, false, false, false, // C....
    true,  false, false, false, false, // C....
    true,  true,  true,  false, false, // CCC..
    false, false, true,  false, false, // ..C..
    false, false, true,  false, false, // ..C..
  ]),
];

// Patrons 7×7 validés par force brute (R4 strict).
const _patterns7x7 = [
  // Patron 0 (lens=[2, 2, 2, 3, 3, 4, 4, 4, 5, 6, 6])
  // CCC.... / ..C.... / ...C... / ....C.. / .....CC / ....... / .......
  _Pattern(rows: 7, cols: 7, mask: [
    true,  true,  true,  false, false, false, false, // CCC....
    false, false, true,  false, false, false, false, // ..C....
    false, false, false, true,  false, false, false, // ...C...
    false, false, false, false, true,  false, false, // ....C..
    false, false, false, false, false, true,  true,  // .....CC
    false, false, false, false, false, false, false, // .......
    false, false, false, false, false, false, false, // .......
  ]),
  // Patron 1 (lens=[2, 3, 3, 4, 4, 4, 4, 5, 6, 6])
  // C...... / C...... / CC..... / ..C.... / ..C.... / ...C... / ...C...
  _Pattern(rows: 7, cols: 7, mask: [
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
    true,  true,  false, false, false, false, false, // CC.....
    false, false, true,  false, false, false, false, // ..C....
    false, false, true,  false, false, false, false, // ..C....
    false, false, false, true,  false, false, false, // ...C...
    false, false, false, true,  false, false, false, // ...C...
  ]),
  // Patron 2 (lens=[2, 2, 3, 3, 4, 4, 5, 6, 6, 6, 6])
  // C...... / C...... / CC..... / ..C.... / ...C... / C...... / C......
  _Pattern(rows: 7, cols: 7, mask: [
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
    true,  true,  false, false, false, false, false, // CC.....
    false, false, true,  false, false, false, false, // ..C....
    false, false, false, true,  false, false, false, // ...C...
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
  ]),
  // Patron 3 (lens=[3, 3, 3, 3, 4, 4, 4, 5, 6, 6])
  // C...... / C...... / CC..... / ..C.... / ...C... / ...C... / ...C...
  _Pattern(rows: 7, cols: 7, mask: [
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
    true,  true,  false, false, false, false, false, // CC.....
    false, false, true,  false, false, false, false, // ..C....
    false, false, false, true,  false, false, false, // ...C...
    false, false, false, true,  false, false, false, // ...C...
    false, false, false, true,  false, false, false, // ...C...
  ]),
  // Patron 4 (lens=[2, 2, 2, 3, 3, 4, 4, 4, 5, 6, 6])
  // C...... / C...... / CC..... / ..C.... / ...C... / ....C.. / ....C..
  _Pattern(rows: 7, cols: 7, mask: [
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
    true,  true,  false, false, false, false, false, // CC.....
    false, false, true,  false, false, false, false, // ..C....
    false, false, false, true,  false, false, false, // ...C...
    false, false, false, false, true,  false, false, // ....C..
    false, false, false, false, true,  false, false, // ....C..
  ]),
  // Patron 5 (lens=[2, 3, 3, 3, 3, 4, 5, 6, 6, 6])
  // C...... / C...... / C...... / CC..... / ..C.... / ...C... / ...C...
  _Pattern(rows: 7, cols: 7, mask: [
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
    true,  false, false, false, false, false, false, // C......
    true,  true,  false, false, false, false, false, // CC.....
    false, false, true,  false, false, false, false, // ..C....
    false, false, false, true,  false, false, false, // ...C...
    false, false, false, true,  false, false, false, // ...C...
  ]),
];

// ---------------------------------------------------------------------------
// Calcul des slots depuis un patron
// ---------------------------------------------------------------------------

List<Slot> _computeSlotsFromPattern(_Pattern pattern) {
  final isClue = pattern.toGrid();
  final slots = <Slot>[];
  final rows = pattern.rows;
  final cols = pattern.cols;

  // Horizontaux
  for (var r = 0; r < rows; r++) {
    var c = 0;
    while (c < cols) {
      if (isClue[r][c]) {
        c++;
        if (c >= cols) break;
        final startC = c;
        while (c < cols && !isClue[r][c]) { c++; }
        final len = c - startC;
        if (len >= 2) {
          slots.add(Slot(
            direction: Direction.horizontal,
            startRow: r,
            startCol: startC,
            length: len,
          ));
        }
      } else {
        c++;
      }
    }
  }

  // Verticaux
  for (var c = 0; c < cols; c++) {
    var r = 0;
    while (r < rows) {
      if (isClue[r][c]) {
        r++;
        if (r >= rows) break;
        final startR = r;
        while (r < rows && !isClue[r][c]) { r++; }
        final len = r - startR;
        if (len >= 2) {
          slots.add(Slot(
            direction: Direction.vertical,
            startRow: startR,
            startCol: c,
            length: len,
          ));
        }
      } else {
        r++;
      }
    }
  }

  return slots;
}

// ---------------------------------------------------------------------------
// État du backtracking
// ---------------------------------------------------------------------------

class _BacktrackState {
  final List<List<String?>> letters;
  final Map<int, KbEntry> placedEntries;
  final int rows;
  final int cols;

  _BacktrackState(this.rows, this.cols)
      : letters = List.generate(rows, (_) => List.filled(cols, null)),
        placedEntries = {};

  List<LetterConstraint> constraintsFor(Slot slot) {
    final result = <LetterConstraint>[];
    final pos = slot.positions;
    for (var i = 0; i < pos.length; i++) {
      final (r, c) = pos[i];
      final existing = letters[r][c];
      if (existing != null) {
        result.add(LetterConstraint(position: i, letter: existing));
      }
    }
    return result;
  }

  void place(int idx, Slot slot, KbEntry entry) {
    placedEntries[idx] = entry;
    final runes = entry.word.runes.toList();
    final pos = slot.positions;
    for (var i = 0; i < pos.length; i++) {
      final (r, c) = pos[i];
      letters[r][c] = String.fromCharCode(runes[i]);
    }
  }

  void unplace(int idx, Slot slot, List<Slot> allSlots) {
    placedEntries.remove(idx);
    for (final (r, c) in slot.positions) {
      var shared = false;
      for (final otherIdx in placedEntries.keys) {
        if (allSlots[otherIdx].positions.contains((r, c))) {
          shared = true;
          break;
        }
      }
      if (!shared) letters[r][c] = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Générateur R4
// ---------------------------------------------------------------------------

class R4Generator {
  final KbRepository kb;

  const R4Generator({required this.kb});

  Future<Grid?> generate(TopologyConfig config) async {
    for (var attempt = 0; attempt < config.maxRetries; attempt++) {
      final seed = _perturbSeed(config.seed, attempt);
      final grid = await _attempt(config, seed, attempt);
      if (grid != null) return grid;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // PHASE A — Sélection du patron
  // -------------------------------------------------------------------------

  _Pattern? _selectPattern(int rows, int cols, int attempt) {
    if (rows == 5 && cols == 5) {
      return _patterns5x5[attempt % _patterns5x5.length];
    }
    if (rows == 7 && cols == 7) {
      return _patterns7x7[attempt % _patterns7x7.length];
    }
    // Taille non supportée.
    return null;
  }

  // -------------------------------------------------------------------------
  // PHASE B — Backtracking
  // -------------------------------------------------------------------------

  List<Slot> _orderSlots(List<Slot> slots) {
    final sorted = List<Slot>.from(slots);
    sorted.sort((a, b) => b.length.compareTo(a.length));
    return sorted;
  }

  Future<bool> _fill(
    int slotIdx,
    List<Slot> orderedSlots,
    _BacktrackState state,
    Random rng,
    DateTime deadline,
  ) async {
    if (DateTime.now().isAfter(deadline)) return false;
    if (slotIdx == orderedSlots.length) return true;

    final slot = orderedSlots[slotIdx];
    final constraints = state.constraintsFor(slot);
    final exclude = state.placedEntries.values.map((e) => e.id).toSet();

    final candidates = await kb.findMatching(
      length: slot.length,
      constraints: constraints,
      excludeIds: exclude,
      limit: 50,
    );

    if (candidates.isEmpty) return false;

    final shuffled = List<KbEntry>.from(candidates)..shuffle(rng);

    for (final entry in shuffled) {
      if (DateTime.now().isAfter(deadline)) return false;
      state.place(slotIdx, slot, entry);
      if (await _fill(slotIdx + 1, orderedSlots, state, rng, deadline)) {
        return true;
      }
      state.unplace(slotIdx, slot, orderedSlots);
    }

    return false;
  }

  // -------------------------------------------------------------------------
  // PHASE C — Construction de la grille
  // -------------------------------------------------------------------------

  Grid _buildGrid(
    List<List<bool>> isClue,
    List<Slot> orderedSlots,
    _BacktrackState state,
    int rows,
    int cols,
    int seed,
  ) {
    final cells = List.generate(rows, (r) {
      return List.generate(cols, (c) {
        if (isClue[r][c]) return ClueCell(clues: const []) as Cell;
        final letter = state.letters[r][c];
        return letter != null
            ? LetterCell(solution: letter) as Cell
            : ClueCell(clues: const []);
      });
    });

    for (var i = 0; i < orderedSlots.length; i++) {
      final slot = orderedSlots[i];
      final entry = state.placedEntries[i];
      if (entry == null) continue;

      final primary = entry.primaryClue;
      if (primary == null) continue;

      final (clueR, clueC) = slot.clueCellPos;
      if (clueR < 0 || clueC < 0 || clueR >= rows || clueC >= cols) continue;
      if (!isClue[clueR][clueC]) continue;

      final clue = Clue(
        text: primary.text,
        language: ClueLanguage.arabic,
        direction: slot.direction,
        solution: entry.wordDisplay,
        startCell: Position(slot.startRow, slot.startCol),
      );

      final existing = cells[clueR][clueC];
      if (existing is ClueCell) {
        cells[clueR][clueC] = ClueCell(clues: [...existing.clues, clue]);
      }
    }

    return Grid(
      rows: rows,
      cols: cols,
      cells: cells,
      variant: GridVariant.standard,
      id: 'day-$seed',
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  // -------------------------------------------------------------------------
  // Tentative complète
  // -------------------------------------------------------------------------

  Future<Grid?> _attempt(TopologyConfig config, int seed, int attempt) async {
    final pattern = _selectPattern(config.rows, config.cols, attempt);
    if (pattern == null) return null;

    final isClue = pattern.toGrid();
    final slots = _computeSlotsFromPattern(pattern);
    if (slots.isEmpty) return null;

    // Vérification couverture KB.
    final requiredLengths = slots.map((s) => s.length).toSet();
    for (final len in requiredLengths) {
      final found = await kb.findMatching(length: len, limit: 1);
      if (found.isEmpty) return null;
    }

    final rng = Random(seed);
    final orderedSlots = _orderSlots(slots);
    final state = _BacktrackState(config.rows, config.cols);
    final deadline =
        DateTime.now().add(Duration(milliseconds: config.backtrackTimeoutMs));

    final success = await _fill(0, orderedSlots, state, rng, deadline);
    if (!success) return null;

    final grid = _buildGrid(
        isClue, orderedSlots, state, config.rows, config.cols, seed);

    if (!_satisfiesR1(grid)) return null;

    return grid;
  }

  bool _satisfiesR1(Grid grid) {
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
      }
    }
    return true;
  }

  int _perturbSeed(int base, int attempt) {
    if (attempt == 0) return base;
    return base * 1009 + attempt * 9973;
  }
}
