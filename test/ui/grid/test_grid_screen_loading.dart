/// Test 1 — Loading state de GridScreen
///
/// Vérifie :
///   1. Pendant le chargement : le message "تحضير شبكة اليوم..." est affiché.
///   2. Une fois le Future résolu : la grille (GridBoard) est affichée.

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

/// Override de puzzleProvider qui retourne un AsyncLoading puis la fixture.
class _FakePuzzleController extends AsyncNotifier<PuzzleState> {
  final Completer<Grid> _completer;

  _FakePuzzleController(this._completer);

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
    // Hive en mode in-memory (pas d'I/O disque en test).
    Hive.init('.');
  });

  testWidgets('GridScreen affiche le message de chargement puis la grille',
      (tester) async {
    final completer = Completer<Grid>();
    final controller = _FakePuzzleController(completer);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puzzleProvider.overrideWith(() => controller),
        ],
        child: const MaterialApp(
          home: GridScreen(),
        ),
      ),
    );

    // État initial = loading
    await tester.pump();
    expect(find.text('تحضير شبكة اليوم...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Résolution du Future
    completer.complete(buildFixtureGrid());
    await tester.pumpAndSettle();

    // Le message de chargement disparaît, la grille s'affiche
    expect(find.text('تحضير شبكة اليوم...'), findsNothing);
    // La ClueBar "sans sélection" est visible
    expect(find.text('اختر حقلاً لقراءة الدليل'), findsOneWidget);
  });
}
