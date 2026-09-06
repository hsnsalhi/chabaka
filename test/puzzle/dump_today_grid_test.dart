/// Dump textuel de la grille du jour pour visualisation hors UI.
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

  test('dump la grille du jour 8×8', () async {
    final repo = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => repo.close());

    final gen = R4Generator(kb: repo);
    final config = TopologyConfig.forDate(DateTime.now(), rows: 8, cols: 8);
    // ignore: avoid_print
    print('Config : rows=${config.rows} cols=${config.cols} seed=${config.seed}');

    final grid = await gen.generate(config);
    expect(grid, isNotNull);

    // ignore: avoid_print
    print('Grid id=${grid!.id}');
    // ignore: avoid_print
    print('Légende : B=Blocker, C=Clue (lettre=solution), .=Letter');
    // ignore: avoid_print
    print('');

    // Header avec numéros de col
    var header = '     ';
    for (var c = 0; c < grid.cols; c++) {
      header += 'c$c '.padLeft(4);
    }
    // ignore: avoid_print
    print(header);

    for (var r = 0; r < grid.rows; r++) {
      var line = 'r$r : ';
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cellAt(Position(r, c));
        if (cell is LetterCell) {
          line += '${cell.solution} '.padLeft(4);
        } else if (cell is ClueCell) {
          if (cell.clues.isEmpty) {
            line += '[B] '.padLeft(4);
          } else {
            final dir = cell.clues.first.direction == Direction.horizontal ? '←' : '↓';
            line += 'C$dir '.padLeft(4);
          }
        } else {
          line += '?  '.padLeft(4);
        }
      }
      // ignore: avoid_print
      print(line);
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('Clues placés (${grid.allClues.length}) :');
    for (final clue in grid.allClues) {
      final dir = clue.direction == Direction.horizontal ? '←' : '↓';
      // ignore: avoid_print
      print('  ${dir} ${clue.solution.padRight(10)} : "${clue.text}"');
    }
  });
}
