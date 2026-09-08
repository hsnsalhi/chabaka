import 'dart:io';

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('today grid: every LC in clued slot, R7 max 2', () async {
    final repo = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
    final config = TopologyConfig.forDate(
      DateTime(2026, 5, 12),
      rows: 8,
      cols: 8,
    );
    final grid = await InterleavedGenerator(kb: repo).generate(config);
    expect(grid, isNotNull);
    final g = grid!;

    final orphans = <Position>[];
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.cols; c++) {
        final cell = g.cellAt(Position(r, c));
        if (cell is! LetterCell) continue;
        bool inAnyClue = false;
        for (final clue in g.allClues) {
          final len = clue.solution.runes.length;
          for (var i = 0; i < len; i++) {
            final p = clue.direction == Direction.horizontal
                ? Position(clue.startCell.row, clue.startCell.col + i)
                : Position(clue.startCell.row + i, clue.startCell.col);
            if (p.row == r && p.col == c) {
              inAnyClue = true;
              break;
            }
          }
          if (inAnyClue) break;
        }
        if (!inAnyClue) orphans.add(Position(r, c));
      }
    }
    // ignore: avoid_print
    print(
      'Orphans: ${orphans.length} ${orphans.map((p) => "(${p.row},${p.col})").join(", ")}',
    );
    expect(orphans, isEmpty, reason: 'Found orphan LCs not in any clued slot');

    // R7 check
    int maxRunH = 0, maxRunV = 0;
    for (var r = 0; r < g.rows; r++) {
      int run = 0;
      for (var c = 0; c < g.cols; c++) {
        if (g.cellAt(Position(r, c)) is ClueCell) {
          run++;
          if (run > maxRunH) maxRunH = run;
        } else
          run = 0;
      }
    }
    for (var c = 0; c < g.cols; c++) {
      int run = 0;
      for (var r = 0; r < g.rows; r++) {
        if (g.cellAt(Position(r, c)) is ClueCell) {
          run++;
          if (run > maxRunV) maxRunV = run;
        } else
          run = 0;
      }
    }
    // ignore: avoid_print
    print('Max consec CC: H=$maxRunH V=$maxRunV');
    expect(maxRunH, lessThanOrEqualTo(2), reason: 'R7 violation H');
    expect(maxRunV, lessThanOrEqualTo(2), reason: 'R7 violation V');

    await repo.close();
  });
}
