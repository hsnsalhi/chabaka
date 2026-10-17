/// Taux de réussite par graine (graines espacées, sans recouvrement) pour une
/// taille de grille et un budget de pas. Outil (tag tool), hors CI.
@Tags(['tool'])
library;

import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _n = int.fromEnvironment('N', defaultValue: 200);
const _steps = int.fromEnvironment(
  'STEPS',
  defaultValue: kDailyMaxStepsPerAttempt,
);
const _rows = int.fromEnvironment('ROWS', defaultValue: 16);
const _cols = int.fromEnvironment('COLS', defaultValue: 11);
const _retries = int.fromEnvironment('RETRIES', defaultValue: 40);

void main() {
  setUpAll(sqfliteFfiInit);
  test('taux de réussite par graine', () async {
    final kb = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(kb.close);
    final gen = TrueInterleavedGenerator(kb: kb);
    var ok = 0;
    final sw = Stopwatch()..start();
    for (var i = 0; i < _n; i++) {
      final g = await gen.generate(
        TopologyConfig(
          rows: _rows,
          cols: _cols,
          seed: 1000003 * (i + 1),
          backtrackTimeoutMs: 30000,
          maxRetries: _retries,
          maxStepsPerAttempt: _steps == 0 ? null : _steps,
        ),
      );
      if (g != null) ok++;
    }
    // ignore: avoid_print
    print(
      'TAUX ${_rows}x$_cols steps=$_steps retries=$_retries : $ok/$_n, '
      '${sw.elapsedMilliseconds ~/ _n} ms par graine',
    );
  }, timeout: const Timeout(Duration(minutes: 60)));
}
