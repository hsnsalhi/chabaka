import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../puzzle/kb/kb_repository_sqflite.dart';
import '../../puzzle/puzzle.dart';
import 'puzzle_state.dart';

/// Ouvre la base SQLite de la KB embarquée (asset → app dir au 1er run).
final kbRepositoryProvider = FutureProvider<KbRepository>((ref) async {
  final repo = await openKbRepositorySqflite();
  ref.onDispose(() async => repo.close());
  return repo;
});

/// Génère (ou charge depuis cache Hive) la grille du jour.
///
/// V1 : 8×8 tuilé (4 sous-régions 4×4 indépendantes, 24 clues).
/// Cache : la grille est sérialisée en JSON dans une box Hive `grid_cache`,
/// clé = grid.id. Premier lancement = ~3 s, ensuite = instantané.
///
/// Side-effect : après le retour de la grille du jour, déclenche en
/// background la génération de la grille de DEMAIN (si pas déjà en
/// cache). Quand minuit passe, l'utilisateur trouve une grille prête
/// à charger sans attente.
final todaysGridProvider = FutureProvider<Grid>((ref) async {
  final cacheBox = await Hive.openBox<String>('grid_cache');
  final today = DateTime.now();
  // V1 réaliste : 8×8 (64 cellules, ~20 CCs). 16×13 (taille Abou Salma)
  // testé mais NON FEASIBLE avec algo+KB courants — backtracking >12min
  // sur FFI, plusieurs heures sur iOS sim. Pour viser 16×13 il faudra :
  //   1. Pré-générer la grille du jour côté backend (job nocturne).
  //   2. OU améliorer l'algo (FFI Rust, multithread).
  //   3. OU pousser la KB à 5000+ entrées pour relâcher les contraintes.
  final config = TopologyConfig.forDate(today, rows: 8, cols: 8);
  final cacheKey = 'day-${config.seed}';

  final cached = cacheBox.get(cacheKey);
  Grid grid;
  if (cached != null) {
    try {
      grid = Grid.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      await cacheBox.delete(cacheKey);
      grid = await _generateAndCache(ref, config, cacheKey, cacheBox);
    }
  } else {
    grid = await _generateAndCache(ref, config, cacheKey, cacheBox);
  }

  // Fire-and-forget : pré-cache la grille de demain.
  Future.microtask(() => _warmupTomorrowCache(ref, today, cacheBox));

  return grid;
});

Future<Grid> _generateAndCache(
  Ref ref,
  TopologyConfig config,
  String cacheKey,
  Box<String> box,
) async {
  final kb = await ref.watch(kbRepositoryProvider.future);
  final grid = await InterleavedGenerator(kb: kb).generate(config);
  if (grid == null) {
    throw StateError('Génération de la grille impossible.');
  }
  await box.put(cacheKey, jsonEncode(grid.toJson()));
  return grid;
}

Future<void> _warmupTomorrowCache(
  Ref ref,
  DateTime today,
  Box<String> box,
) async {
  try {
    final tomorrow = today.add(const Duration(days: 1));
    final config = TopologyConfig.forDate(tomorrow, rows: 8, cols: 8);
    final cacheKey = 'day-${config.seed}';
    if (box.containsKey(cacheKey)) return;

    final kb = await ref.read(kbRepositoryProvider.future);
    final grid = await InterleavedGenerator(kb: kb).generate(config);
    if (grid != null) {
      await box.put(cacheKey, jsonEncode(grid.toJson()));
    }
  } catch (_) {
    // Best-effort : si la pré-génération échoue, l'utilisateur attendra
    // demain normalement. Pas de log pour ne pas polluer.
  }
}

/// État de jeu : grille, cellule sélectionnée, validation courante.
/// Persiste les userInput dans Hive (box scopée par grille).
final puzzleProvider =
    AsyncNotifierProvider<PuzzleController, PuzzleState>(PuzzleController.new);

class PuzzleController extends AsyncNotifier<PuzzleState> {
  static const _validator = GridValidator();
  Box<String>? _box;

  @override
  Future<PuzzleState> build() async {
    final grid = await ref.watch(todaysGridProvider.future);
    final box = await Hive.openBox<String>('grid_${grid.id}');
    _box = box;

    for (final entry in grid.letterCells) {
      final saved = box.get(_key(entry.pos));
      if (saved != null && saved.isNotEmpty) {
        entry.cell.userInput = saved;
      }
    }

    return PuzzleState(
      grid: grid,
      selected: null,
      validation: _validator.validateGrid(grid),
    );
  }

  void selectCell(Position pos) {
    final current = state.valueOrNull;
    if (current == null) return;

    final cell = current.grid.cellAt(pos);
    if (cell is! LetterCell) return;

    // Re-tap sur la cellule sélectionnée : si elle est à l'intersection
    // d'un mot H et d'un mot V, on bascule l'activeDirection.
    if (current.selected == pos) {
      final coversH = _findClueCoveringInDir(current.grid, pos, Direction.horizontal);
      final coversV = _findClueCoveringInDir(current.grid, pos, Direction.vertical);
      if (coversH != null && coversV != null) {
        state = AsyncData(current.copyWith(
          activeDirection: current.activeDirection == Direction.horizontal
              ? Direction.vertical
              : Direction.horizontal,
        ));
      }
      return;
    }

    // Nouvelle sélection : si la cellule n'est dans qu'une direction,
    // on adopte celle-là ; sinon on garde la direction courante.
    final coversH = _findClueCoveringInDir(current.grid, pos, Direction.horizontal);
    final coversV = _findClueCoveringInDir(current.grid, pos, Direction.vertical);
    Direction newDir = current.activeDirection;
    if (coversH != null && coversV == null) newDir = Direction.horizontal;
    if (coversV != null && coversH == null) newDir = Direction.vertical;

    state = AsyncData(current.copyWith(
      selected: pos,
      activeDirection: newDir,
    ));
  }

  Clue? _findClueCoveringInDir(Grid grid, Position pos, Direction dir) {
    for (final clue in grid.allClues) {
      if (clue.direction != dir) continue;
      final positions = _cluePositions(clue);
      if (positions.contains(pos)) return clue;
    }
    return null;
  }

  void clearSelection() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearSelected: true));
  }

  void setLetter(Position pos, String? input) {
    final current = state.valueOrNull;
    if (current == null) return;
    final cell = current.grid.cellAt(pos);
    if (cell is! LetterCell) return;

    final cleaned = (input ?? '').trim();
    cell.userInput = cleaned.isEmpty ? null : cleaned;

    final box = _box;
    if (box != null) {
      if (cell.userInput == null) {
        box.delete(_key(pos));
      } else {
        box.put(_key(pos), cell.userInput!);
      }
    }

    state = AsyncData(current.copyWith(
      validation: _validator.validateGrid(current.grid),
    ));
  }

  /// Tape une lettre dans [pos] et avance la sélection à la cellule
  /// suivante du mot actif (selon `state.activeDirection`).
  /// L'utilisateur remplit un mot d'affilée sans re-taper à chaque case
  /// (auto-advance — UX option A).
  void typeLetter(Position pos, String letter) {
    setLetter(pos, letter);
    final current = state.valueOrNull;
    if (current == null) return;
    final next = _nextLetterCellInActiveWord(current, pos);
    if (next != null) {
      state = AsyncData(current.copyWith(selected: next));
    }
  }

  /// Géré par le clavier : si la case est vide, recule d'une case dans
  /// le mot actif et vide la case précédente. Sinon, vide simplement
  /// la case courante (sans bouger).
  void backspace() {
    final current = state.valueOrNull;
    if (current == null) return;
    final pos = current.selected;
    if (pos == null) return;
    final cell = current.grid.cellAt(pos);
    if (cell is! LetterCell) return;

    if ((cell.userInput ?? '').isNotEmpty) {
      // Vide la case courante, reste dessus.
      setLetter(pos, null);
      return;
    }
    // Déjà vide → recule dans le mot actif et vide la précédente.
    final prev = _previousLetterCellInActiveWord(current, pos);
    if (prev != null) {
      state = AsyncData(current.copyWith(selected: prev));
      setLetter(prev, null);
    }
  }

  Position? _nextLetterCellInActiveWord(PuzzleState s, Position pos) {
    final clue = _findClueCoveringInDir(s.grid, pos, s.activeDirection);
    if (clue == null) {
      // Fallback : prend la 1re direction où la cellule est couverte.
      return _nextLetterCellAnyDir(s.grid, pos);
    }
    final positions = _cluePositions(clue);
    final idx = positions.indexOf(pos);
    if (idx >= 0 && idx < positions.length - 1) {
      final next = positions[idx + 1];
      if (s.grid.cellAt(next) is LetterCell) return next;
    }
    return null;
  }

  Position? _previousLetterCellInActiveWord(PuzzleState s, Position pos) {
    final clue = _findClueCoveringInDir(s.grid, pos, s.activeDirection);
    if (clue == null) return null;
    final positions = _cluePositions(clue);
    final idx = positions.indexOf(pos);
    if (idx > 0) {
      final prev = positions[idx - 1];
      if (s.grid.cellAt(prev) is LetterCell) return prev;
    }
    return null;
  }

  Position? _nextLetterCellAnyDir(Grid grid, Position pos) {
    for (final dir in [Direction.horizontal, Direction.vertical]) {
      for (final clue in grid.allClues) {
        if (clue.direction != dir) continue;
        final positions = _cluePositions(clue);
        final idx = positions.indexOf(pos);
        if (idx >= 0 && idx < positions.length - 1) {
          final next = positions[idx + 1];
          if (grid.cellAt(next) is LetterCell) return next;
        }
      }
    }
    return null;
  }

  List<Position> _cluePositions(Clue clue) {
    final len = clue.solution.runes.length;
    return List.generate(len, (i) {
      return clue.direction == Direction.horizontal
          ? Position(clue.startCell.row, clue.startCell.col + i)
          : Position(clue.startCell.row + i, clue.startCell.col);
    });
  }

  /// Efface toutes les saisies — utile pour reset (non exposé dans l'UI V1).
  Future<void> reset() async {
    final current = state.valueOrNull;
    if (current == null) return;
    for (final entry in current.grid.letterCells) {
      entry.cell.userInput = null;
    }
    await _box?.clear();
    state = AsyncData(current.copyWith(
      validation: _validator.validateGrid(current.grid),
    ));
  }

  String _key(Position p) => '${p.row},${p.col}';
}

/// Indique si une cellule fait partie du mot actif.
bool isInActiveWord(Grid grid, Position cellPos, Position? selected) {
  if (selected == null) return false;
  for (final clue in grid.allClues) {
    if (!_clueCoversPosition(clue, selected)) continue;
    if (_clueCoversPosition(clue, cellPos)) return true;
  }
  return false;
}

bool _clueCoversPosition(Clue clue, Position pos) {
  final len = clue.solution.runes.length;
  for (var i = 0; i < len; i++) {
    final p = clue.direction == Direction.horizontal
        ? Position(clue.startCell.row, clue.startCell.col + i)
        : Position(clue.startCell.row + i, clue.startCell.col);
    if (p == pos) return true;
  }
  return false;
}
