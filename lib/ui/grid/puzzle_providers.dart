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

/// Génère la grille du jour via R4Generator (déterministe par date).
final todaysGridProvider = FutureProvider<Grid>((ref) async {
  final kb = await ref.watch(kbRepositoryProvider.future);
  final generator = R4Generator(kb: kb);
  // V1 : 4×4 par défaut. Avec 264 entrées seed (111 len-3, 64 len-4),
  // les grilles plus grandes (5×4, 4×5, 5×5) sont trop contraintes :
  // les V slots de longueur 4 demandent des combinaisons letter-cross
  // dont seules ~6e-8 % sont des mots arabes valides. Pour 5×5+ il
  // faudra 200+ mots len-4 (cf. task #13 PO/éditorial).
  // 4 patrons 4×4 disponibles → 4 layouts différents possibles selon
  // les seeds quotidiens.
  final config = TopologyConfig.forDate(DateTime.now(), rows: 4, cols: 4);
  final grid = await generator.generate(config);
  if (grid == null) {
    throw StateError('Génération de la grille impossible.');
  }
  return grid;
});

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
    if (current.selected == pos) return;
    state = AsyncData(current.copyWith(selected: pos));
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
