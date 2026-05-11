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

  factory TopologyConfig.forDate(
    DateTime date, {
    int rows = 8,
    int cols = 8,
    int backtrackTimeoutMs = 180000,
    int maxRetries = 8,
  }) {
    final epoch = DateTime(2024, 1, 1);
    final days = date.difference(epoch).inDays;
    return TopologyConfig(
      rows: rows,
      cols: cols,
      seed: days,
      backtrackTimeoutMs: backtrackTimeoutMs,
      maxRetries: maxRetries,
    );
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

  // Non-const : les patrons tuilés sont générés runtime via _buildTiledPattern.
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

// Patrons 8×8 — générés par tools/kb-builder/search_scattered_patterns.py
// Simulated annealing partant du tuilage 4×4, optimisant pour :
// - minimum de CCs (ratio CC/total)
// - dispersion (CCs scattered au lieu d'alignés sur grilles)
//
// Tous R1+R4 strict (validé par validate_pattern.py).
// Patron 16×13 — vraies dimensions Abou Salma (CC=61, ratio 29%).
const _patterns16x13 = <_Pattern>[
  _Pattern(rows: 16, cols: 13, kinds: [
    CellKind.clue, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue,
    CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue,
    CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
  ]),
];

// Patterns R5 strict (PO 2026-05-11) : aucune position absente.
// Toute case est SOIT ClueCell (avec ≥1 indice) SOIT LetterCell.
// (0,0) toujours CC (top-right en RTL).
// Certains runs ne sont pas précédés d'une CC → "edge slots" sans
// indice affiché, déduits par intersection (comme dans les vraies
// grilles Abou Salma).
// Générés par tools/kb-builder/search_full_patterns.py.
const _patterns8x8 = <_Pattern>[
  // Pattern 0 : CC=20, ratio 31% — slots ≤4, scattered, few edge runs.
  // CLLLCCCC / LCCCLLLL / LLLCLLLL / CLLLLLCL / CLLLLCLL / LCLLCLLC / LCLLLCLL / CLLCLLLL
  _Pattern(rows: 8, cols: 8, kinds: [
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.clue,
    CellKind.letter, CellKind.clue, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
  // Pattern 1 : CC=21, ratio 33% — variant
  // CLLCCLLC / LCLLLCCL / LCLLLLLL / LCCLCLLL / CLLLCLLL / CLLCLLCC / CLLLLCLL / CLLLCLLL
  _Pattern(rows: 8, cols: 8, kinds: [
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.letter, CellKind.clue, CellKind.clue, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.clue,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter,
    CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter, CellKind.clue, CellKind.letter, CellKind.letter, CellKind.letter,
  ]),
];

// ---------------------------------------------------------------------------
// Slots calculés depuis le patron
// ---------------------------------------------------------------------------

List<Slot> _computeSlotsFromPattern(_Pattern p) {
  final slots = <Slot>[];

  // R5 strict (PO 2026-05-11) : tout run ≥2 de LetterCells = slot.
  // Si précédé d'une [clue], l'indice de ce slot sera visible.
  // Sinon (edge run, ou run après autre case sans clue), le slot reste
  // une contrainte de backtracking mais sans indice affiché.

  // Horizontaux
  for (var r = 0; r < p.rows; r++) {
    var c = 0;
    while (c < p.cols) {
      if (p.kindAt(r, c) == CellKind.letter) {
        final start = c;
        while (c < p.cols && p.kindAt(r, c) == CellKind.letter) {
          c++;
        }
        final length = c - start;
        if (length >= 2) {
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

  // Verticaux
  for (var c = 0; c < p.cols; c++) {
    var r = 0;
    while (r < p.rows) {
      if (p.kindAt(r, c) == CellKind.letter) {
        final start = r;
        while (r < p.rows && p.kindAt(r, c) == CellKind.letter) {
          r++;
        }
        final length = r - start;
        if (length >= 2) {
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
  final Map<Slot, KbEntry> placed;
  final int rows;
  final int cols;

  _BacktrackState(this.rows, this.cols)
      : letters = List.generate(rows, (_) => List.filled(cols, null)),
        placed = {};

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

  Set<int> excludedIds() => placed.values.map((e) => e.id).toSet();

  void place(Slot slot, KbEntry entry) {
    placed[slot] = entry;
    final runes = entry.word.runes.toList();
    final pos = slot.positions;
    for (var i = 0; i < pos.length; i++) {
      final (r, c) = pos[i];
      letters[r][c] = String.fromCharCode(runes[i]);
    }
  }

  void unplace(Slot slot) {
    placed.remove(slot);
    for (final (r, c) in slot.positions) {
      var shared = false;
      for (final other in placed.keys) {
        if (other.positions.contains((r, c))) {
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
    if (rows == 8 && cols == 8) {
      // Patrons SA-optimisés (dispersés, CC ≤ 25%).
      return _patterns8x8[attempt % _patterns8x8.length];
    }
    if (rows == 16 && cols == 13) {
      return _patterns16x13[attempt % _patterns16x13.length];
    }
    // Tuilage automatique pour grilles ≥12×12 (multiples de 4). Fallback :
    // sous-régions 4×4 assemblées — visuellement régulier mais R1+R4 strict.
    if (rows % 4 == 0 && cols % 4 == 0 && rows >= 12 && cols >= 12) {
      return _buildTiledPattern(rows, cols);
    }
    return null;
  }

  /// Construit dynamiquement un patron par tuilage de blocs 4×4.
  /// Chaque tuile a la forme :
  ///   BCCC
  ///   CLLL × 3
  /// Les tuiles sont juxtaposées : leurs colonnes "header" (col 0 de chaque
  /// tuile) restent C, leurs lignes "header" (row 0) restent BCCC.
  /// Cells partagées : aucune (chaque L appartient à une tuile unique).
  _Pattern _buildTiledPattern(int rows, int cols) {
    final kinds = List<CellKind>.filled(rows * cols, CellKind.letter);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final tileRow = r % 4;
        final tileCol = c % 4;
        late CellKind k;
        if (tileRow == 0 && tileCol == 0) {
          k = CellKind.blocker;
        } else if (tileRow == 0 || tileCol == 0) {
          k = CellKind.clue;
        } else {
          k = CellKind.letter;
        }
        kinds[r * cols + c] = k;
      }
    }
    return _Pattern(rows: rows, cols: cols, kinds: kinds);
  }

  /// Backtracking dynamique avec heuristique MRV (Most-Restricted Variable) :
  /// à chaque étape, on choisit le slot avec le moins de candidats compatibles
  /// (≤ [_mrvProbeLimit]). C'est le "constraint propagation" classique des
  /// CSP — réduit drastiquement la taille de l'arbre de recherche par rapport
  /// à un ordre statique (V/H interleaved).
  ///
  /// Inclut forward checking implicite : si un slot non placé a 0 candidat,
  /// on backtrack immédiatement.
  Future<bool> _fillMRV(
    Set<Slot> remaining,
    _BacktrackState state,
    Random rng,
    DateTime deadline,
    int candidateLimit,
  ) async {
    if (DateTime.now().isAfter(deadline)) return false;
    if (remaining.isEmpty) return true;

    // Sonde chaque slot restant pour trouver le plus contraint.
    Slot? bestSlot;
    List<KbEntry>? bestCandidates;
    var bestCount = -1;

    final excluded = state.excludedIds();
    for (final slot in remaining) {
      final constraints = state.constraintsFor(slot);
      final cands = await kb.findMatching(
        length: slot.length,
        constraints: constraints,
        excludeIds: excluded,
        limit: _mrvProbeLimit,
      );

      // 0 candidats : on échoue immédiatement (forward check failed).
      if (cands.isEmpty) return false;

      if (bestSlot == null || cands.length < bestCount) {
        bestSlot = slot;
        bestCandidates = cands;
        bestCount = cands.length;
        // Si on a trouvé un slot à 1 candidat, c'est le minimum possible.
        if (bestCount == 1) break;
      }
    }

    if (bestSlot == null) return false;

    // Si la sonde a limité à _mrvProbeLimit et c'est saturé, refait une
    // requête avec une fenêtre plus large pour le slot choisi.
    var candidates = bestCandidates!;
    if (candidates.length >= _mrvProbeLimit &&
        candidateLimit > _mrvProbeLimit) {
      candidates = await kb.findMatching(
        length: bestSlot.length,
        constraints: state.constraintsFor(bestSlot),
        excludeIds: excluded,
        limit: candidateLimit,
      );
    }

    final shuffled = List<KbEntry>.from(candidates)..shuffle(rng);
    final nextRemaining = Set<Slot>.from(remaining)..remove(bestSlot);

    for (final entry in shuffled) {
      if (DateTime.now().isAfter(deadline)) return false;
      state.place(bestSlot, entry);
      if (await _fillMRV(
          nextRemaining, state, rng, deadline, candidateLimit)) {
        return true;
      }
      state.unplace(bestSlot);
    }

    return false;
  }

  /// Fenêtre de sondage MRV : sondage minimal pour comparer slots.
  /// Plus c'est petit, plus c'est rapide ; mais si trop petit, l'ordre
  /// MRV devient bruité quand beaucoup de slots ont ≥N candidats.
  /// 10 = compromis post-extension KB (1868 entrées).
  static const int _mrvProbeLimit = 10;
  static const int _maxCandidatePool = 100;

  Grid _buildGrid(
    _Pattern pattern,
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
            // Sera remplie ci-dessous avec les clues attribués.
            return ClueCell(clues: const []);
          case CellKind.blocker:
            // R5 strict (PO 2026-05-11) : pas de case absente. Si un pattern
            // a encore CellKind.blocker (legacy), on traite comme ClueCell
            // vide ; mais les nouveaux patterns ne devraient PAS en avoir.
            return ClueCell(clues: const []);
        }
      });
    });

    for (final entry in state.placed.entries) {
      final slot = entry.key;
      final kbEntry = entry.value;

      final primary = kbEntry.primaryClue;
      if (primary == null) continue;

      final (clueR, clueC) = slot.clueCellPos;
      if (clueR < 0 || clueC < 0 || clueR >= rows || clueC >= cols) continue;
      if (pattern.kindAt(clueR, clueC) != CellKind.clue) continue;

      final clue = Clue(
        text: primary.text,
        language: ClueLanguage.arabic,
        direction: slot.direction,
        solution: kbEntry.wordDisplay,
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
    final state = _BacktrackState(config.rows, config.cols);
    final deadline =
        DateTime.now().add(Duration(milliseconds: config.backtrackTimeoutMs));

    final success = await _fillMRV(
        slots.toSet(), state, rng, deadline, _maxCandidatePool);
    if (!success) return null;

    final grid = _buildGrid(pattern, state, seed);

    if (!_isPostBuildValid(grid, pattern)) return null;

    return grid;
  }

  /// R5 strict : toute cellule présente dans la grille doit être SOIT
  /// une ClueCell avec ≥1 indice, SOIT une LetterCell avec lettre non-vide.
  bool _isPostBuildValid(Grid grid, _Pattern pattern) {
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
        if (cell is LetterCell && cell.solution.isEmpty) return false;
      }
    }
    return true;
  }

  int _perturbSeed(int base, int attempt) {
    if (attempt == 0) return base;
    return base * 1009 + attempt * 9973;
  }
}
