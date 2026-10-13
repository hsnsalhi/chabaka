/// Exporte une grille générée (TrueInterleavedGenerator) en JSON pour les
/// outils externes (page Facebook, rendu image). Pas un test de régression :
/// tag `tool`, exclu de la CI.
///
/// Usage :
///   flutter test test/tools/export_grid_test.dart --tags tool \
///     --dart-define=ROWS=8 --dart-define=COLS=7 --dart-define=SEED=123 \
///     --dart-define=MAX_DIFF=2 --dart-define=OUT=/tmp/grid.json
@Tags(['tool'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _rows = int.fromEnvironment('ROWS', defaultValue: 8);
const _cols = int.fromEnvironment('COLS', defaultValue: 7);
const _seed = int.fromEnvironment('SEED', defaultValue: 0);
const _maxDiff = int.fromEnvironment('MAX_DIFF', defaultValue: 0);
const _out = String.fromEnvironment('OUT', defaultValue: 'build/grid.json');

void main() {
  setUpAll(sqfliteFfiInit);

  test('exporte une grille en JSON', () async {
    final repo = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
    addTearDown(() async => repo.close());

    final baseSeed = _seed != 0
        ? _seed
        : DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000;
    final gen = TrueInterleavedGenerator(kb: repo);
    Grid? grid;
    var seed = baseSeed;
    // Comme l'app : on essaie plusieurs graines consécutives.
    for (var offset = 0; offset < 40 && grid == null; offset++) {
      seed = baseSeed + offset;
      grid = await gen.generate(
        TopologyConfig(
          rows: _rows,
          cols: _cols,
          seed: seed,
          backtrackTimeoutMs: 20000,
          maxRetries: 8,
          maxDifficulty: _maxDiff == 0 ? null : _maxDiff,
        ),
      );
    }
    expect(grid, isNotNull, reason: 'aucune grille (graines $baseSeed..$seed)');

    final json = grid!.toJson();
    json['seed'] = seed;
    json['generatedAt'] = DateTime.now().toUtc().toIso8601String();
    final file = File(_out)..parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    // ignore: avoid_print
    print(
      'OK ${grid.rows}x${grid.cols} seed=$seed '
      'clues=${grid.allClues.length} → $_out',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
