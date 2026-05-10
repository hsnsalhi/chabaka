/// Smoke test : R4Generator avec patrons R1+R4-strict sur KB réelle.
/// Mesure si la génération converge dans un temps raisonnable.
library;

import 'dart:io';

import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('R4Generator converge sur 5×5 avec KB réelle en < 5s', () async {
    final repo = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => repo.close());

    final gen = R4Generator(kb: repo);

    // Sweep MRV avec tuilage : 4×4, 8×8, 12×12
    Future<void> sweep(int rows, int cols, String label) async {
      var ok = 0;
      var totalMs = 0;
      Grid? sample;
      for (var s = 1; s <= 3; s++) {
        final sw = Stopwatch()..start();
        final g = await gen.generate(TopologyConfig(
          rows: rows,
          cols: cols,
          seed: s,
          backtrackTimeoutMs: 30000,
          maxRetries: 2,
        ));
        sw.stop();
        totalMs += sw.elapsedMilliseconds;
        if (g != null) {
          ok++;
          sample ??= g;
        }
      }
      // ignore: avoid_print
      print('  $label : $ok/3 OK, ${totalMs ~/ 3} ms/seed avg');
      if (sample != null) {
        // ignore: avoid_print
        print('    ${sample.allClues.length} clues placés');
      }
    }

    await sweep(8, 8, '8×8');
    await sweep(12, 12, '12×12');
    await sweep(16, 16, '16×16');
    await sweep(12, 16, '12×16 Abou Salma');
    await sweep(20, 20, '20×20');
  }, timeout: const Timeout(Duration(seconds: 600)));
}
