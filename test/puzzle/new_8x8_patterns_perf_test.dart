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

  test('8×8 scattered pattern converge', () async {
    final repo = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );

    final gen = R4Generator(kb: repo);
    var ok = 0;
    var totalMs = 0;
    Grid? sample;
    for (var seed = 1; seed <= 3; seed++) {
      final sw = Stopwatch()..start();
      final grid = await gen.generate(
        TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 30000,
          maxRetries: 3,
        ),
      );
      sw.stop();
      totalMs += sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('  seed=$seed: ${sw.elapsedMilliseconds}ms grid=${grid != null}');
      if (grid != null) {
        ok++;
        sample ??= grid;
      }
    }
    // ignore: avoid_print
    print('Total : $ok/3 OK, avg=${totalMs ~/ 3}ms');

    await repo.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
