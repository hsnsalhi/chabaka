/// Mesure la génération de la grille du jour (13×9, jusqu'à 100 graines) avec
/// un budget de pas donné : durée totale, graines essayées, plus long appel
/// synchrone. Outil (tag tool), hors CI.
///
///   flutter test test/tools/daily_timing_test.dart --tags tool \
///     --dart-define=DAYS=14 --dart-define=STEPS=4000 [--dart-define=KB=…]
@Tags(['tool'])
library;

import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _days = int.fromEnvironment('DAYS', defaultValue: 7);
const _steps = int.fromEnvironment(
  'STEPS',
  defaultValue: kDailyMaxStepsPerAttempt,
);
const _kb = String.fromEnvironment(
  'KB',
  defaultValue: 'assets/kb/chabaka_kb.sqlite',
);
const _maxDiff = int.fromEnvironment('MAX_DIFF', defaultValue: 0);
const _rows = int.fromEnvironment('ROWS', defaultValue: 13);
const _cols = int.fromEnvironment('COLS', defaultValue: 9);

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'génération quotidienne : temps par graine',
    () async {
      final path = _kb.startsWith('/') ? _kb : '${Directory.current.path}/$_kb';
      final kb = await openKbRepositoryFromFile(
        path,
        databaseFactoryOverride: databaseFactoryFfi,
      );
      addTearDown(kb.close);
      final gen = TrueInterleavedGenerator(kb: kb);
      final start = DateTime(2026, 10, 14);
      var worst = 0;
      var fails = 0;
      var sum = 0;
      for (var d = 0; d < _days; d++) {
        final date = start.add(Duration(days: d));
        final base = TopologyConfig.forDate(
          date,
          rows: _rows,
          cols: _cols,
          maxStepsPerAttempt: _steps == 0 ? null : _steps,
          maxDifficulty: _maxDiff == 0 ? null : _maxDiff,
        );
        final total = Stopwatch()..start();
        var longest = 0;
        var tries = 0;
        Grid? grid;
        for (var off = 0; off < 100 && grid == null; off++) {
          tries++;
          final sw = Stopwatch()..start();
          grid = await gen.generate(base.withSeed(base.seed + off));
          sw.stop();
          if (sw.elapsedMilliseconds > longest)
            longest = sw.elapsedMilliseconds;
        }
        total.stop();
        if (grid == null) fails++;
        sum += total.elapsedMilliseconds;
        if (total.elapsedMilliseconds > worst)
          worst = total.elapsedMilliseconds;
        // ignore: avoid_print
        print(
          '${date.toIso8601String().substring(0, 10)} : '
          '${grid != null ? "OK" : "ÉCHEC"} en ${total.elapsedMilliseconds} ms, '
          '$tries graine(s), plus long appel $longest ms',
        );
      }
      // ignore: avoid_print
      print(
        'BILAN steps=$_steps : moyenne ${sum ~/ _days} ms, pire $worst ms, '
        'échecs $fails/$_days',
      );
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
