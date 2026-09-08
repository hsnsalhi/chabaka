/// Test rigoureux : pour chaque grille générée, vérifie qu'AUCUN run de
/// ≥2 LetterCells consécutives n'existe sans qu'une ClueCell porteuse
/// d'un indice ne précède directement le run.
/// Ce test exerce R4Generator (moteur historique, non utilisé par l'app
/// depuis le passage à TrueInterleavedGenerator). Tag `legacy` : exclu de la
/// CI, exécutable localement avec `flutter test --tags legacy`.
@Tags(['legacy'])
library;

import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('R4 STRICT : aucun run ≥2 sans ClueCell prédécesseure (8×8)', () async {
    final repo = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => repo.close());

    final gen = R4Generator(kb: repo);

    for (var seed = 1; seed <= 5; seed++) {
      final grid = await gen.generate(
        TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 5000,
          maxRetries: 3,
        ),
      );
      if (grid == null) {
        // ignore: avoid_print
        print('seed=$seed : pas de grille générée — skip');
        continue;
      }

      final violations = _findR4Violations(grid);
      expect(
        violations,
        isEmpty,
        reason:
            'Seed $seed produit des runs orphelins : ${violations.join(', ')}',
      );
    }
  });
}

/// Cherche tous les runs ≥2 de LetterCells consécutives (H + V) qui n'ont
/// pas une ClueCell **avec ≥1 indice** immédiatement avant eux.
/// Une ClueCell vide (blocker) NE compte PAS comme prédécesseure valide.
List<String> _findR4Violations(Grid grid) {
  final violations = <String>[];

  // Horizontal
  for (var r = 0; r < grid.rows; r++) {
    var c = 0;
    while (c < grid.cols) {
      if (grid.cellAt(Position(r, c)) is LetterCell) {
        final start = c;
        while (c < grid.cols && grid.cellAt(Position(r, c)) is LetterCell) {
          c++;
        }
        final length = c - start;
        if (length >= 2) {
          // Le prédécesseur doit exister + être une ClueCell avec clues
          if (start == 0) {
            violations.add(
              'H run ($r,$start) len=$length sans prédécesseur (col 0)',
            );
          } else {
            final pred = grid.cellAt(Position(r, start - 1));
            if (pred is! ClueCell || pred.clues.isEmpty) {
              violations.add(
                'H run ($r,$start) len=$length, prédécesseur ($r,${start - 1}) = ${pred.runtimeType} (clues vides ou non-Clue)',
              );
            }
          }
        }
      } else {
        c++;
      }
    }
  }

  // Vertical
  for (var c = 0; c < grid.cols; c++) {
    var r = 0;
    while (r < grid.rows) {
      if (grid.cellAt(Position(r, c)) is LetterCell) {
        final start = r;
        while (r < grid.rows && grid.cellAt(Position(r, c)) is LetterCell) {
          r++;
        }
        final length = r - start;
        if (length >= 2) {
          if (start == 0) {
            violations.add(
              'V run ($start,$c) len=$length sans prédécesseur (row 0)',
            );
          } else {
            final pred = grid.cellAt(Position(start - 1, c));
            if (pred is! ClueCell || pred.clues.isEmpty) {
              violations.add(
                'V run ($start,$c) len=$length, prédécesseur (${start - 1},$c) = ${pred.runtimeType} (clues vides ou non-Clue)',
              );
            }
          }
        }
      } else {
        r++;
      }
    }
  }

  return violations;
}
