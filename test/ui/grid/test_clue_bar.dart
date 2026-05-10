/// Test 2 — ClueBar
///
/// Vérifie :
///   1. Sans sélection : ClueBar affiche "اختر حقلاً لقراءة الدليل".
///   2. Tap sur la 1re LetterCell du mot H → ClueBar affiche le texte de
///      l'indice H ("قراءة وكتابة") ET la flèche "←".

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/grid_screen.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/grid/puzzle_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '_fixtures.dart';

/// PuzzleController synchrone — pas de Hive, grille fournie directement.
class _SyncPuzzleController extends AsyncNotifier<PuzzleState> {
  final Grid _grid;

  _SyncPuzzleController(this._grid);

  @override
  Future<PuzzleState> build() async {
    return PuzzleState(
      grid: _grid,
      selected: null,
      validation: buildEmptyValidation(_grid),
    );
  }

  @override
  void selectCell(Position pos) {
    final current = state.valueOrNull;
    if (current == null) return;
    final cell = current.grid.cellAt(pos);
    if (cell is! LetterCell) return;

    if (current.selected == pos) {
      // Toggle direction si intersection.
      final coversH = _findClue(current.grid, pos, Direction.horizontal);
      final coversV = _findClue(current.grid, pos, Direction.vertical);
      if (coversH != null && coversV != null) {
        state = AsyncData(current.copyWith(
          activeDirection: current.activeDirection == Direction.horizontal
              ? Direction.vertical
              : Direction.horizontal,
        ));
      }
      return;
    }

    final coversH = _findClue(current.grid, pos, Direction.horizontal);
    final coversV = _findClue(current.grid, pos, Direction.vertical);
    Direction newDir = current.activeDirection;
    if (coversH != null && coversV == null) newDir = Direction.horizontal;
    if (coversV != null && coversH == null) newDir = Direction.vertical;

    state = AsyncData(current.copyWith(selected: pos, activeDirection: newDir));
  }

  Clue? _findClue(Grid grid, Position pos, Direction dir) {
    for (final clue in grid.allClues) {
      if (clue.direction != dir) continue;
      final len = clue.solution.runes.length;
      for (var i = 0; i < len; i++) {
        final p = dir == Direction.horizontal
            ? Position(clue.startCell.row, clue.startCell.col + i)
            : Position(clue.startCell.row + i, clue.startCell.col);
        if (p == pos) return clue;
      }
    }
    return null;
  }
}

void main() {
  setUpAll(() async {
    Hive.init('.');
  });

  testWidgets('ClueBar — sans sélection affiche le message invite',
      (tester) async {
    final grid = buildFixtureGrid();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puzzleProvider.overrideWith(() => _SyncPuzzleController(grid)),
        ],
        child: const MaterialApp(home: GridScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اختر حقلاً لقراءة الدليل'), findsOneWidget);
    expect(find.text('←'), findsNothing);
  });

  testWidgets('ClueBar — tap sur cellule H affiche indice + flèche ←',
      (tester) async {
    final grid = buildFixtureGrid();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puzzleProvider.overrideWith(() => _SyncPuzzleController(grid)),
        ],
        child: const MaterialApp(home: GridScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap sur le 1er TextField (= cellule (0,1) = 'ك', 1re lettre du mot H).
    // On tape via le focus : tap sur le champ texte.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // La ClueBar doit maintenant afficher l'indice du mot H.
    expect(find.text('قراءة وكتابة'), findsOneWidget);
    // Et la flèche H (RTL → affichée comme ←)
    expect(
      find.text('←'),
      findsWidgets, // peut apparaître aussi dans les ClueCells
    );
    // Le message invite ne doit plus être affiché.
    expect(find.text('اختر حقلاً لقراءة الدليل'), findsNothing);
  });
}
