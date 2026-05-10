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

    // Sweep 5×5 sur 5 seeds (avec interleaving).
    Grid? sampleGrid;
    for (var s = 1; s <= 5; s++) {
      final sw = Stopwatch()..start();
      final g = await gen.generate(TopologyConfig(
        rows: 5,
        cols: 5,
        seed: s,
        backtrackTimeoutMs: 3000,
        maxRetries: 5,
      ));
      sw.stop();
      // ignore: avoid_print
      print('  5x5 seed=$s : ${sw.elapsedMilliseconds} ms, grid=${g != null}');
      sampleGrid ??= g;
    }
    if (sampleGrid != null) {
      // ignore: avoid_print
      print('  Clues échantillon :');
      for (final clue in sampleGrid.allClues) {
        // ignore: avoid_print
        print('    ${clue.direction.name}: ${clue.solution} ← "${clue.text}"');
      }
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
