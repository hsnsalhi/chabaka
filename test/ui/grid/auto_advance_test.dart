/// Test 3 — Auto-advance
///
/// Vérifie :
///   - Après saisie d'une lettre en (0,1), la sélection avance à (0,2).
///   - Après saisie en (0,2), avance à (0,3).
///   - En fin de mot (0,3), la sélection reste en (0,3).

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/grid/puzzle_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '_fixtures.dart';

/// Sous-classe de PuzzleController qui court-circuite Hive et sqflite.
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

  group('auto-advance — mot H "كتب" (0,1)→(0,2)→(0,3)', () {
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

    test('avance de (0,1) à (0,2) après typeLetter', () async {
      await container.read(puzzleProvider.future);

      container.read(puzzleProvider.notifier).selectCell(const Position(0, 1));
      container.read(puzzleProvider.notifier).typeLetter(
            const Position(0, 1),
            'ك',
          );

      final state = container.read(puzzleProvider).valueOrNull;
      expect(
        state?.selected,
        const Position(0, 2),
        reason: 'après typeLetter en (0,1), sélection doit être en (0,2)',
      );
    });

    test('avance de (0,2) à (0,3) après typeLetter', () async {
      await container.read(puzzleProvider.future);

      container.read(puzzleProvider.notifier).selectCell(const Position(0, 1));
      container.read(puzzleProvider.notifier).typeLetter(
            const Position(0, 1),
            'ك',
          );
      container.read(puzzleProvider.notifier).typeLetter(
            const Position(0, 2),
            'ت',
          );

      final state = container.read(puzzleProvider).valueOrNull;
      expect(
        state?.selected,
        const Position(0, 3),
        reason: 'après typeLetter en (0,2), sélection doit être en (0,3)',
      );
    });

    test('reste en (0,3) après typeLetter en fin de mot', () async {
      await container.read(puzzleProvider.future);

      container.read(puzzleProvider.notifier).selectCell(const Position(0, 3));
      container.read(puzzleProvider.notifier).typeLetter(
            const Position(0, 3),
            'ب',
          );

      final state = container.read(puzzleProvider).valueOrNull;
      expect(
        state?.selected,
        const Position(0, 3),
        reason: 'en fin de mot, la sélection doit rester sur la dernière case',
      );
    });
  });
}
