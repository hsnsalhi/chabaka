/// Test 3 — Auto-advance
///
/// Vérifie :
///   - Après tap sur la 1re lettre d'un mot H + saisie d'un caractère,
///     la sélection avance à la case suivante.
///   - En fin de mot, la sélection reste en dernière case.

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/grid/puzzle_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '_fixtures.dart';

void main() {
  setUpAll(() async {
    Hive.init('.');
  });

  testWidgets('auto-advance après saisie d\'une lettre dans un mot H',
      (tester) async {
    final grid = buildFixtureGrid();
    // Mot H "كتب" : (0,1) → (0,2) → (0,3)

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puzzleProvider.overrideWith(
            () => _DirectPuzzleController(grid),
          ),
        ],
        child: _TestApp(grid: grid),
      ),
    );
    await tester.pumpAndSettle();

    final container = tester.element(find.byType(_TestApp)).providerContainer;

    // Sélectionner la cellule (0,1) — 1re lettre du mot H.
    container.read(puzzleProvider.notifier).selectCell(const Position(0, 1));
    await tester.pump();

    // Vérifier la sélection initiale.
    expect(
      container.read(puzzleProvider).valueOrNull?.selected,
      const Position(0, 1),
    );

    // Taper 'ك' → doit avancer à (0,2).
    container.read(puzzleProvider.notifier).typeLetter(
          const Position(0, 1),
          'ك',
        );
    await tester.pump();

    expect(
      container.read(puzzleProvider).valueOrNull?.selected,
      const Position(0, 2),
      reason: 'après typeLetter en (0,1), la sélection doit être en (0,2)',
    );

    // Taper 'ت' → doit avancer à (0,3).
    container.read(puzzleProvider.notifier).typeLetter(
          const Position(0, 2),
          'ت',
        );
    await tester.pump();

    expect(
      container.read(puzzleProvider).valueOrNull?.selected,
      const Position(0, 3),
      reason: 'après typeLetter en (0,2), la sélection doit être en (0,3)',
    );

    // Taper 'ب' en (0,3) = dernière lettre → pas d'avance (fin de mot).
    container.read(puzzleProvider.notifier).typeLetter(
          const Position(0, 3),
          'ب',
        );
    await tester.pump();

    expect(
      container.read(puzzleProvider).valueOrNull?.selected,
      const Position(0, 3),
      reason: 'en fin de mot, la sélection doit rester sur la dernière case',
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Widget minimal qui expose son ProviderContainer via l'arbre.
class _TestApp extends StatelessWidget {
  final Grid grid;

  const _TestApp({required this.grid});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
  }
}

extension on WidgetTester {
  // ignore: unused_element
}

extension on Element {
  ProviderContainer get providerContainer {
    ProviderContainer? container;
    visitAncestorElements((element) {
      if (element is ProviderScopeElement) {
        container = element.container;
        return false;
      }
      return true;
    });
    return container!;
  }
}

extension on ProviderScopeElement {
  ProviderContainer get container =>
      (this as dynamic).container as ProviderContainer;
}

/// PuzzleController synchrone minimal pour les tests auto-advance.
class _DirectPuzzleController extends AsyncNotifier<PuzzleState> {
  final Grid _grid;

  _DirectPuzzleController(this._grid);

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
