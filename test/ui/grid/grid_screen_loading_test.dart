/// Test 1 — Loading state de GridScreen
///
/// Vérifie :
///   1. Pendant le chargement : "تحضير شبكة اليوم..." est affiché.
///   2. Une fois le Future résolu : la grille est affichée (ClueBar visible).

import 'dart:async';

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/grid_screen.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/grid/puzzle_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '_fixtures.dart';

/// Controller qui bloque sur un Completer puis retourne la fixture.
class _DelayedPuzzleController extends PuzzleController {
  final Completer<Grid> _completer;

  _DelayedPuzzleController(this._completer);

  @override
  Future<PuzzleState> build() async {
    final grid = await _completer.future;
    return PuzzleState(
      grid: grid,
      selected: null,
      validation: buildEmptyValidation(grid),
    );
  }
}

void main() {
  setUpAll(() async {
    Hive.init('.');
  });

  testWidgets('GridScreen affiche le message de chargement puis la grille',
      (tester) async {
    final completer = Completer<Grid>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puzzleProvider.overrideWith(
            () => _DelayedPuzzleController(completer),
          ),
        ],
        child: const MaterialApp(home: GridScreen()),
      ),
    );

    // 1 pump pour lancer le Future (loading).
    await tester.pump();
    expect(find.text('تحضير شبكة اليوم...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Résolution du Future → grille disponible.
    completer.complete(buildFixtureGrid());
    await tester.pumpAndSettle();

    // Message de chargement disparu.
    expect(find.text('تحضير شبكة اليوم...'), findsNothing);
    // ClueBar sans sélection visible = grille chargée.
    expect(find.text('اختر حقلاً لقراءة الدليل'), findsOneWidget);
  });
}
