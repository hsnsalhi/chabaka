/// Test de performance longue durée. Tag `perf` : exclu de la CI,
/// exécutable localement avec `flutter test --tags perf`.
@Tags(['perf'])
library;

import 'dart:io';

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    '16×13 Abou Salma pattern converge',
    () async {
      final repo = await openKbRepositoryFromFile(
        '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
        databaseFactoryOverride: databaseFactoryFfi,
      );

      final gen = InterleavedGenerator(kb: repo);
      final sw = Stopwatch()..start();
      final grid = await gen.generate(
        const TopologyConfig(
          rows: 16,
          cols: 13,
          seed: 100,
          backtrackTimeoutMs: 600000, // 10 min max
          maxRetries: 3,
        ),
      );
      sw.stop();
      // ignore: avoid_print
      print(
        '16×13 seed=100 : ${sw.elapsedMilliseconds}ms grid=${grid != null}',
      );
      if (grid != null) {
        // ignore: avoid_print
        print(
          '  ${grid.allClues.length} clues placés sur ${grid.rows}×${grid.cols} = ${grid.rows * grid.cols} cellules',
        );
      }
      await repo.close();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
