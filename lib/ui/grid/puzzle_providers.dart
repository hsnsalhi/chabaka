import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../puzzle/puzzle.dart';
import 'puzzle_state.dart';

/// Charge la wordlist arabe depuis les assets.
final wordlistProvider = FutureProvider<Wordlist>((ref) async {
  final raw = await rootBundle.loadString('assets/wordlist/wordlist_ar.json');
  return Wordlist.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});

/// Génère la grille du jour (déterministe par date).
final todaysGridProvider = FutureProvider<Grid>((ref) async {
  final wordlist = await ref.watch(wordlistProvider.future);
  final generator = PuzzleGenerator(wordlist: wordlist);
  final config = GeneratorConfig.forDate(DateTime.now());
  final grid = generator.generate(config);
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

/// Indique si une cellule fait partie du mot actif (= mot lié à la cellule
/// sélectionnée, dans la direction par défaut horizontale ; on ne gère pas
/// le toggle direction en V1).
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
