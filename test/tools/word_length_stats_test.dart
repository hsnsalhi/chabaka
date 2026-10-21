/// Effet de la longueur maximale des mots et de la préférence pour les mots
/// longs : taux de réussite par graine, temps, proportion de cases-définitions
/// et longueur moyenne des mots. Outil (tag tool), hors CI.
///
///   flutter test test/tools/word_length_stats_test.dart --tags tool \
///     --dart-define=ROWS=13 --dart-define=COLS=9 --dart-define=MAXLEN=7 \
///     --dart-define=BIAS=2 --dart-define=DENSITY=0.12 --dart-define=N=100
@Tags(['tool'])
library;

import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _n = int.fromEnvironment('N', defaultValue: 100);
const _rows = int.fromEnvironment('ROWS', defaultValue: 13);
const _cols = int.fromEnvironment('COLS', defaultValue: 9);
const _maxLen = int.fromEnvironment('MAXLEN', defaultValue: 5);
const _bias = String.fromEnvironment('BIAS', defaultValue: '0');
const _density = String.fromEnvironment('DENSITY', defaultValue: '0.18');
const _maxDiff = int.fromEnvironment('MAX_DIFF', defaultValue: 0);

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'statistiques de longueur des mots',
    () async {
      final kb = await openKbRepositoryFromFile(
        '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
        databaseFactoryOverride: databaseFactoryFfi,
      );
      addTearDown(kb.close);
      final gen = TrueInterleavedGenerator(kb: kb);
      var ok = 0;
      var clueCells = 0;
      var cells = 0;
      var words = 0;
      var letters = 0;
      var longest = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < _n; i++) {
        final t = Stopwatch()..start();
        final g = await gen.generate(
          TopologyConfig(
            rows: _rows,
            cols: _cols,
            seed: 1000003 * (i + 1),
            backtrackTimeoutMs: 30000,
            maxRetries: 40,
            maxStepsPerAttempt: kDailyMaxStepsPerAttempt,
            maxWordLen: _maxLen,
            longWordBias: double.parse(_bias),
            minClueDensity: double.parse(_density),
            maxDifficulty: _maxDiff == 0 ? null : _maxDiff,
          ),
        );
        if (t.elapsedMilliseconds > longest) longest = t.elapsedMilliseconds;
        if (g == null) continue;
        ok++;
        for (final row in g.cells) {
          for (final c in row) {
            cells++;
            if (c is ClueCell) clueCells++;
          }
        }
        for (final clue in g.allClues) {
          words++;
          letters += clue.solution.runes.length;
        }
      }
      // ignore: avoid_print
      print(
        'STATS ${_rows}x$_cols maxLen=$_maxLen bias=$_bias density=$_density : '
        'réussite $ok/$_n, ${sw.elapsedMilliseconds ~/ _n} ms/graine '
        '(max $longest), cases-définitions '
        '${ok == 0 ? 0 : (100 * clueCells / cells).toStringAsFixed(1)} %, '
        'mot moyen ${ok == 0 ? 0 : (letters / words).toStringAsFixed(2)} lettres',
      );
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
