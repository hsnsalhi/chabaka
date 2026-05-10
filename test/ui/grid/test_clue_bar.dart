/// Test 2 — ClueBar
///
/// Vérifie :
///   1. Sans sélection : ClueBar affiche "اختر حقلاً لقراءة الدليل".
///   2. Tap sur le 1er TextField (= 1re LetterCell du mot H) → ClueBar
///      affiche le texte de l'indice H ("قراءة وكتابة") + flèche "←".

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/grid_screen.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/grid/puzzle_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '_fixtures.dart';

/// Sous-classe de PuzzleController, build() synchrone sans Hive.
class _FakePuzzleController extends PuzzleController {
  final Grid _grid;

  _FakePuzzleController(this._grid);

  @override
  Future<PuzzleState> build() async {
    return PuzzleState(
      grid: _grid,
      selected: null,
      validation: buildEmptyValidation(_grid),
    );
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
          puzzleProvider.overrideWith(() => _FakePuzzleController(grid)),
        ],
        child: const MaterialApp(home: GridScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اختر حقلاً لقراءة الدليل'), findsOneWidget);
  });

  testWidgets('ClueBar — tap sur 1re LetterCell affiche indice H + flèche ←',
      (tester) async {
    final grid = buildFixtureGrid();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puzzleProvider.overrideWith(() => _FakePuzzleController(grid)),
        ],
        child: const MaterialApp(home: GridScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap sur le 1er TextField = cellule (0,1) = 'ك', 1re lettre du mot H.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // L'indice du mot H doit apparaître (dans la ClueBar + dans la ClueCellWidget).
    expect(find.text('قراءة وكتابة'), findsWidgets);
    // La flèche H (←) doit être visible.
    expect(find.text('←'), findsWidgets);
    // Le message invite ne doit plus être affiché.
    expect(find.text('اختر حقلاً لقراءة الدليل'), findsNothing);
  });
}
