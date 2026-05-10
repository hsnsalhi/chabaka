/// Test 4 — Direction toggle
///
/// Vérifie qu'un re-tap sur une cellule à l'intersection H∩V bascule
/// l'activeDirection : H → V → H.
///
/// Dans la fixture : Position(0,1) est à l'intersection du mot H "كتب"
/// et du mot V "كر".

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

  group('direction toggle sur cellule d\'intersection (0,1)', () {
    late ProviderContainer container;

    setUp(() {
      final grid = buildFixtureGrid();
      container = ProviderContainer(
        overrides: [
          puzzleProvider.overrideWith(() => _FakePuzzleController(grid)),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('1er tap → direction H (par défaut)', () async {
      await container.read(puzzleProvider.future);
      container.read(puzzleProvider.notifier).selectCell(const Position(0, 1));

      final state = container.read(puzzleProvider).valueOrNull;
      expect(state?.selected, const Position(0, 1));
      expect(state?.activeDirection, Direction.horizontal);
    });

    test('2e tap sur la même cellule → direction bascule à V', () async {
      await container.read(puzzleProvider.future);
      final notifier = container.read(puzzleProvider.notifier);

      notifier.selectCell(const Position(0, 1)); // 1er tap → H
      notifier.selectCell(const Position(0, 1)); // 2e tap → V

      final state = container.read(puzzleProvider).valueOrNull;
      expect(state?.activeDirection, Direction.vertical,
          reason: 're-tap sur intersection doit basculer H→V');
    });

    test('3e tap → direction revient à H', () async {
      await container.read(puzzleProvider.future);
      final notifier = container.read(puzzleProvider.notifier);

      notifier.selectCell(const Position(0, 1)); // H
      notifier.selectCell(const Position(0, 1)); // V
      notifier.selectCell(const Position(0, 1)); // H

      final state = container.read(puzzleProvider).valueOrNull;
      expect(state?.activeDirection, Direction.horizontal,
          reason: '3e tap doit revenir à H');
    });
  });
}
