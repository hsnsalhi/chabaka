/// Moteur R4 — Topology-First Slot-Filling Backtracking.
///
/// Garanties (cf. docs/grid-rules.md) :
///   R1 (relâchée le 2026-05-10) : toute case est soit
///     - une ClueCell avec ≥ 1 indice (case type [CellKind.clue]),
///     - soit une LetterCell couverte par ≥ 1 mot,
///     - soit un Blocker visuel (case type [CellKind.blocker]) — équivalent
///       d'une case noire dans les vraies grilles مسهمة Abou Salma.
///   R4 strict : toute suite ≥ 2 lettres consécutives (H ou V) est un mot
///     du dictionnaire **avec une ClueCell prédécesseure** qui héberge
///     son indice. Pas de runs orphelins.
///
/// Stratégie :
///   PHASE A — Sélection d'un patron pré-validé (les patrons sont générés
///             par `tools/kb-builder/generate_patterns.py` puis vérifiés
///             par `validate_pattern.py`).
///   PHASE B — Backtracking slot par slot avec requêtes KB.
///   PHASE C — Construction de la Grid (clues attachées aux cases [clue],
///             blockers laissés vides, lettres remplies depuis le state).

library;

import 'dart:math';

import '../kb/kb_repository.dart';
import '../models.dart';

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
  final int backtrackTimeoutMs;
  final int maxRetries;

  const TopologyConfig({
    required this.rows,
    required this.cols,
    required this.seed,
    this.backtrackTimeoutMs = 2000,
    this.maxRetries = 40,
  });

  factory TopologyConfig.forDate(DateTime date, {int rows = 5, int cols = 4}) {
    final epoch = DateTime(2024, 1, 1);
    final days = date.difference(epoch).inDays;
    return TopologyConfig(rows: rows, cols: cols, seed: days);
  }
}

// ---------------------------------------------------------------------------
// CellKind — l'enum public (utilisé par les const _Pattern et tests)
// ---------------------------------------------------------------------------

enum CellKind { letter, clue, blocker }

class _Pattern {
  final int rows;
  final int cols;
  final List<CellKind> kinds; // length = rows*cols, row-major

  const _Pattern({
    required this.rows,
    required this.cols,
    required this.kinds,
  });

  CellKind kindAt(int r, int c) => kinds[r * cols + c];
}

// ---------------------------------------------------------------------------
// Patrons pré-validés (R1 relâchée + R4 strict)
// Générés par tools/kb-builder/validate_pattern.py.
// ---------------------------------------------------------------------------

const _patterns5x4 = <_Pattern>[
  // Patron 0 : BCCC / CLLL / CLLL / CLLL / CLLL — 4 H slots len 3, 3 V slots len 4
  _Pattern(rows: 5, cols: 4, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
];

const _patterns4x5 = <_Pattern>[
  // Patron 0 : BCCCC / CLLLL / CLLLL / CLLLL — 3 H slots len 4, 4 V slots len 3
  _Pattern(rows: 4, cols: 5, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
];

const _patterns4x4 = <_Pattern>[
  // Patron 0 : BCCC / CLLL / CLLL / CLLL — 3 H slots × len 3, 3 V slots × len 3 (9 L)
  _Pattern(rows: 4, cols: 4, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
  // Patron 1 : BCCC / CLLL / CLLL / CLLB — blocker en bas-droite (8 L)
  _Pattern(rows: 4, cols: 4, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.blocker,
  ]),
  // Patron 2 : BCCB / CLLC / CLLL / CLLL — blocker haut-droite + clue interne (8 L)
  _Pattern(rows: 4, cols: 4, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.blocker,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
];

const _patterns5x5 = <_Pattern>[
  // Patron 0 : BCCCC / CLLLL / CLLLL / CLLLL / CLLLL
  _Pattern(rows: 5, cols: 5, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
  // Patron 1 : BCCCC / CLLLL / CLLLL / CLLLL / CLLLB
  _Pattern(rows: 5, cols: 5, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.blocker,
  ]),
];

const _patterns7x7 = <_Pattern>[
  // Patron 0 : BCCCCCC / 6× CLLLLLL
  _Pattern(rows: 7, cols: 7, kinds: [
    CellKind.blocker, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
];

// ---------------------------------------------------------------------------
// Slots calculés depuis le patron
// ---------------------------------------------------------------------------

List<Slot> _computeSlotsFromPattern(_Pattern p) {
  final slots = <Slot>[];

  // Horizontaux : run de [letter] précédé immédiatement d'une [clue].
  for (var r = 0; r < p.rows; r++) {
    var c = 0;
    while (c < p.cols) {
      if (p.kindAt(r, c) == CellKind.letter) {
        final start = c;
        while (c < p.cols && p.kindAt(r, c) == CellKind.letter) {
          c++;
        }
        final length = c - start;
        if (length >= 2 &&
            start >= 1 &&
            p.kindAt(r, start - 1) == CellKind.clue) {
          slots.add(Slot(
            direction: Direction.horizontal,
            startRow: r,
            startCol: start,
            length: length,
          ));
        }
      } else {
        c++;
      }
    }
  }

  // Verticaux : idem mais en colonne.
  for (var c = 0; c < p.cols; c++) {
    var r = 0;
    while (r < p.rows) {
      if (p.kindAt(r, c) == CellKind.letter) {
        final start = r;
        while (r < p.rows && p.kindAt(r, c) == CellKind.letter) {
          r++;
        }
        final length = r - start;
        if (length >= 2 &&
            start >= 1 &&
            p.kindAt(start - 1, c) == CellKind.clue) {
          slots.add(Slot(
            direction: Direction.vertical,
            startRow: start,
            startCol: c,
            length: length,
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

  _Pattern? _selectPattern(int rows, int cols, int attempt) {
    if (rows == 4 && cols == 4) {
      return _patterns4x4[attempt % _patterns4x4.length];
    }
    if (rows == 5 && cols == 4) {
      return _patterns5x4[attempt % _patterns5x4.length];
    }
    if (rows == 4 && cols == 5) {
      return _patterns4x5[attempt % _patterns4x5.length];
    }
    if (rows == 5 && cols == 5) {
      return _patterns5x5[attempt % _patterns5x5.length];
    }
    if (rows == 7 && cols == 7) {
      return _patterns7x7[attempt % _patterns7x7.length];
    }
    return null;
  }

  /// Ordonne les slots en alternant V/H pour maximiser la propagation
  /// de contraintes (chaque slot ajouté est croisé par les précédents).
  /// Sans cet entrelacement, tous les V longs sont placés sans contrainte
  /// mutuelle, et les H finissent surcontraints → backtracking exponentiel.
  List<Slot> _orderSlots(List<Slot> slots) {
    final verticals = slots
        .where((s) => s.direction == Direction.vertical)
        .toList()
      ..sort((a, b) {
        final byLen = b.length.compareTo(a.length);
        return byLen != 0 ? byLen : a.startCol.compareTo(b.startCol);
      });
    final horizontals = slots
        .where((s) => s.direction == Direction.horizontal)
        .toList()
      ..sort((a, b) {
        final byLen = b.length.compareTo(a.length);
        return byLen != 0 ? byLen : a.startRow.compareTo(b.startRow);
      });

    final ordered = <Slot>[];
    final maxLen = verticals.length > horizontals.length
        ? verticals.length
        : horizontals.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < verticals.length) ordered.add(verticals[i]);
      if (i < horizontals.length) ordered.add(horizontals[i]);
    }
    return ordered;
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

  Grid _buildGrid(
    _Pattern pattern,
    List<Slot> orderedSlots,
    _BacktrackState state,
    int seed,
  ) {
    final rows = pattern.rows;
    final cols = pattern.cols;

    final cells = List<List<Cell>>.generate(rows, (r) {
      return List<Cell>.generate(cols, (c) {
        switch (pattern.kindAt(r, c)) {
          case CellKind.letter:
            final letter = state.letters[r][c];
            return LetterCell(solution: letter ?? '');
          case CellKind.clue:
            return ClueCell(clues: const []);
          case CellKind.blocker:
            return ClueCell(clues: const []);
        }
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
      if (pattern.kindAt(clueR, clueC) != CellKind.clue) continue;

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

  Future<Grid?> _attempt(
      TopologyConfig config, int seed, int attempt) async {
    final pattern = _selectPattern(config.rows, config.cols, attempt);
    if (pattern == null) return null;

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

    final grid = _buildGrid(pattern, orderedSlots, state, seed);

    if (!_isPostBuildValid(grid, pattern)) return null;

    return grid;
  }

  /// Vérifie que les ClueCell de type [clue] dans le pattern ont bien
  /// reçu au moins 1 indice après la construction (sinon : bug de génération).
  /// Les ClueCell de type [blocker] ont droit d'être vides (par design).
  bool _isPostBuildValid(Grid grid, _Pattern pattern) {
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final kind = pattern.kindAt(r, c);
        final cell = grid.cells[r][c];
        if (kind == CellKind.clue && cell is ClueCell && cell.clues.isEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  int _perturbSeed(int base, int attempt) {
    if (attempt == 0) return base;
    return base * 1009 + attempt * 9973;
  }
}
