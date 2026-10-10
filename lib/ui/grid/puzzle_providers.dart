import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/game/game_options.dart';
import '../../puzzle/kb/kb_repository_sqflite.dart';
import '../../puzzle/puzzle.dart';
import 'puzzle_state.dart';

/// Ouvre la base SQLite de la KB embarquée (asset → app dir au 1er run).
final kbRepositoryProvider = FutureProvider<KbRepository>((ref) async {
  final repo = await openKbRepositorySqflite();
  ref.onDispose(() async => repo.close());
  return repo;
});

// ---------------------------------------------------------------------------
// Provider "options de la partie courante"
// ---------------------------------------------------------------------------

/// Injecté par GameScreen avant que puzzleProvider ne soit construit.
/// GameScreen l'écrase via ProviderScope overrides ou StateProvider.
final currentGameOptionsProvider = StateProvider<GameOptions>(
  (ref) => GameOptions.daily(),
);

// ---------------------------------------------------------------------------
// Génération grille Daily
// ---------------------------------------------------------------------------

/// Génère (ou charge depuis cache Hive) la grille du jour.
///
/// V1 : 13×9 (dimensions intermédiaire standard Chabaka, plus haute que large).
/// Cache : la grille est sérialisée en JSON dans une box Hive `grid_cache`,
/// clé = grid.id. Premier lancement = ~3 s, ensuite = instantané.
final todaysGridProvider = FutureProvider<Grid>((ref) async {
  final cacheBox = await Hive.openBox<String>('grid_cache');
  final today = DateTime.now();
  final config = TopologyConfig.forDate(today, rows: 13, cols: 9);
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

/// Nombre de seeds dérivés essayés, dans un ordre fixe, avant d'abandonner.
const _kDailySeedAttempts = 100;

/// Génère la grille d'un jour de façon **déterministe** : les seeds dérivés
/// sont essayés dans le même ordre sur tous les appareils, donc tout le monde
/// obtient la même grille pour une même date. Retourne null si aucun seed
/// ne converge.
Future<Grid?> generateDailyGrid(KbRepository kb, TopologyConfig config) async {
  final generator = TrueInterleavedGenerator(kb: kb);
  for (var offset = 0; offset < _kDailySeedAttempts; offset++) {
    final tryConfig = TopologyConfig(
      rows: config.rows,
      cols: config.cols,
      seed: config.seed + offset,
      backtrackTimeoutMs: config.backtrackTimeoutMs,
      maxRetries: config.maxRetries,
      categories: config.categories,
    );
    final grid = await generator.generate(tryConfig);
    if (grid != null) return grid;
  }
  return null;
}

Future<Grid> _generateAndCache(
  Ref ref,
  TopologyConfig config,
  String cacheKey,
  Box<String> box,
) async {
  final kb = await ref.watch(kbRepositoryProvider.future);
  final grid = await generateDailyGrid(kb, config);
  if (grid == null) {
    throw StateError(
      'Génération de la grille impossible ($_kDailySeedAttempts seeds tentés).',
    );
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
    final config = TopologyConfig.forDate(tomorrow, rows: 13, cols: 9);
    final cacheKey = 'day-${config.seed}';
    if (box.containsKey(cacheKey)) return;

    final kb = await ref.read(kbRepositoryProvider.future);
    final grid = await generateDailyGrid(kb, config);
    if (grid != null) {
      await box.put(cacheKey, jsonEncode(grid.toJson()));
    }
  } catch (_) {
    // Best-effort.
  }
}

// ---------------------------------------------------------------------------
// Génération grille Quick
// ---------------------------------------------------------------------------

/// Seed de la partie rapide courante. Incrémenté à chaque "Nouvelle grille".
final quickSeedProvider = StateProvider<int>((ref) {
  return DateTime.now().millisecondsSinceEpoch;
});

/// Génère une grille à la volée pour le mode Quick.
/// Dépend de [currentGameOptionsProvider] et [quickSeedProvider].
final quickGridProvider = FutureProvider<Grid>((ref) async {
  final opts = ref.watch(currentGameOptionsProvider);
  final seed = ref.watch(quickSeedProvider);
  final kb = await ref.watch(kbRepositoryProvider.future);

  final config = TopologyConfig(
    rows: opts.rows,
    cols: opts.cols,
    seed: seed,
    backtrackTimeoutMs: 120000,
    maxRetries: 40,
    categories: opts.categoriesFilter,
  );

  Grid? grid;
  for (var i = 0; i < 50; i++) {
    final tryConfig = TopologyConfig(
      rows: config.rows,
      cols: config.cols,
      seed: config.seed + i,
      backtrackTimeoutMs: config.backtrackTimeoutMs,
      maxRetries: config.maxRetries,
      categories: config.categories,
    );
    grid = await TrueInterleavedGenerator(kb: kb).generate(tryConfig);
    if (grid != null) break;
  }
  if (grid == null) {
    throw StateError('Génération grille rapide impossible.');
  }
  return grid;
});

// ---------------------------------------------------------------------------
// Provider principal puzzle — commun Daily + Quick
// ---------------------------------------------------------------------------

/// État de jeu : grille, cellule sélectionnée, validation courante.
/// Lit [currentGameOptionsProvider] pour choisir la source (daily / quick).
final puzzleProvider = AsyncNotifierProvider<PuzzleController, PuzzleState>(
  PuzzleController.new,
);

class PuzzleController extends AsyncNotifier<PuzzleState> {
  static const _validator = GridValidator();
  Box<String>? _box;

  @override
  Future<PuzzleState> build() async {
    final opts = ref.watch(currentGameOptionsProvider);

    final Grid grid;
    if (opts.mode == GameMode.daily) {
      grid = await ref.watch(todaysGridProvider.future);
    } else {
      grid = await ref.watch(quickGridProvider.future);
    }

    // Pour le daily, persiste les inputs. Pour le quick, box jetable.
    final boxName = opts.mode == GameMode.daily
        ? 'grid_${grid.id}'
        : 'quick_${grid.id}';
    final box = await Hive.openBox<String>(boxName);
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

    if (current.selected == pos) {
      final coversH = _findClueCoveringInDir(
        current.grid,
        pos,
        Direction.horizontal,
      );
      final coversV = _findClueCoveringInDir(
        current.grid,
        pos,
        Direction.vertical,
      );
      if (coversH != null && coversV != null) {
        state = AsyncData(
          current.copyWith(
            activeDirection: current.activeDirection == Direction.horizontal
                ? Direction.vertical
                : Direction.horizontal,
          ),
        );
      }
      return;
    }

    final coversH = _findClueCoveringInDir(
      current.grid,
      pos,
      Direction.horizontal,
    );
    final coversV = _findClueCoveringInDir(
      current.grid,
      pos,
      Direction.vertical,
    );
    Direction newDir = current.activeDirection;
    if (coversH != null && coversV == null) newDir = Direction.horizontal;
    if (coversV != null && coversH == null) newDir = Direction.vertical;

    state = AsyncData(current.copyWith(selected: pos, activeDirection: newDir));
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

    state = AsyncData(
      current.copyWith(validation: _validator.validateGrid(current.grid)),
    );
  }

  void typeLetter(Position pos, String letter) {
    setLetter(pos, letter);
    final current = state.valueOrNull;
    if (current == null) return;
    final next = _nextLetterCellInActiveWord(current, pos);
    if (next != null) {
      state = AsyncData(current.copyWith(selected: next));
    }
  }

  void backspace() {
    final current = state.valueOrNull;
    if (current == null) return;
    final pos = current.selected;
    if (pos == null) return;
    final cell = current.grid.cellAt(pos);
    if (cell is! LetterCell) return;

    if ((cell.userInput ?? '').isNotEmpty) {
      setLetter(pos, null);
      return;
    }
    final prev = _previousLetterCellInActiveWord(current, pos);
    if (prev != null) {
      state = AsyncData(current.copyWith(selected: prev));
      setLetter(prev, null);
    }
  }

  Position? _nextLetterCellInActiveWord(PuzzleState s, Position pos) {
    final clue = _findClueCoveringInDir(s.grid, pos, s.activeDirection);
    if (clue == null) {
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

  Future<void> reset() async {
    final current = state.valueOrNull;
    if (current == null) return;
    for (final entry in current.grid.letterCells) {
      entry.cell.userInput = null;
    }
    await _box?.clear();
    state = AsyncData(
      current.copyWith(validation: _validator.validateGrid(current.grid)),
    );
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
