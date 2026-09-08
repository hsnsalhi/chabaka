/// Test 5 — Backspace retreat
///
/// Vérifie :
///   1. Backspace sur cellule remplie → vide la case, sélection reste.
///   2. Backspace sur cellule vide → recule d'une case ET vide la précédente.
///
/// Mot H "كتب" : (0,1)=ك (0,2)=ت (0,3)=ب

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/grid/puzzle_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '_fixtures.dart';

class _FakePuzzleController extends PuzzleController {
  final Grid _grid;

  _FakePuzzleController(this._grid);

  @override
  Future<PuzzleState> build() async {
    return PuzzleState(
      grid: _grid,
      selected: null,
      activeDirection: Direction.horizontal,
      validation: buildEmptyValidation(_grid),
    );
  }
}

void main() {
  setUpAll(() async {
    Hive.init('.');
  });

  group('backspace', () {
    late ProviderContainer container;
    late Grid grid;

    setUp(() {
      grid = buildFixtureGrid();
      container = ProviderContainer(
        overrides: [
          puzzleProvider.overrideWith(() => _FakePuzzleController(grid)),
        ],
      );
    });

    tearDown(() => container.dispose());

    test(
      'backspace sur cellule remplie — vide la case, sélection reste',
      () async {
        await container.read(puzzleProvider.future);
        final notifier = container.read(puzzleProvider.notifier);

        // Placer la sélection sur (0,2) et y mettre une lettre.
        notifier.selectCell(const Position(0, 2));
        notifier.setLetter(const Position(0, 2), 'ت');

        // Vérifier que la cellule est remplie.
        final cellBefore = grid.cellAt(const Position(0, 2)) as LetterCell;
        expect(cellBefore.userInput, 'ت');

        // Backspace.
        notifier.backspace();

        final state = container.read(puzzleProvider).valueOrNull;
        expect(
          state?.selected,
          const Position(0, 2),
          reason: 'la sélection ne doit pas bouger',
        );
        final cellAfter = grid.cellAt(const Position(0, 2)) as LetterCell;
        expect(
          cellAfter.userInput,
          isNull,
          reason: 'la cellule doit être vidée',
        );
      },
    );

    test(
      'backspace sur cellule vide — recule d\'une case et vide la précédente',
      () async {
        await container.read(puzzleProvider.future);
        final notifier = container.read(puzzleProvider.notifier);

        // Remplir (0,1) et (0,2), se positionner sur (0,2) vide.
        notifier.setLetter(const Position(0, 1), 'ك');
        notifier.selectCell(const Position(0, 2));
        // (0,2) est vide (aucun setLetter dessus).

        // Backspace sur cellule vide.
        notifier.backspace();

        final state = container.read(puzzleProvider).valueOrNull;
        // La sélection doit reculer à (0,1).
        expect(
          state?.selected,
          const Position(0, 1),
          reason: 'backspace sur cellule vide doit reculer la sélection',
        );
        // Et (0,1) doit être vidée.
        final prevCell = grid.cellAt(const Position(0, 1)) as LetterCell;
        expect(
          prevCell.userInput,
          isNull,
          reason: 'la cellule précédente doit être vidée par backspace',
        );
      },
    );

    test(
      'backspace en 1re case du mot — ne recule pas (pas de case précédente)',
      () async {
        await container.read(puzzleProvider.future);
        final notifier = container.read(puzzleProvider.notifier);

        // Se positionner sur (0,1) = 1re lettre du mot H, case vide.
        notifier.selectCell(const Position(0, 1));

        notifier.backspace();

        final state = container.read(puzzleProvider).valueOrNull;
        // Pas de case précédente → sélection reste en (0,1).
        expect(
          state?.selected,
          const Position(0, 1),
          reason:
              'en 1re case du mot, backspace ne doit pas changer la sélection',
        );
      },
    );
  });
}
