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
// COUNT > 1 : génère une série de grilles, OUT est alors un dossier
// (fichiers grid_<seed>.json).
const _count = int.fromEnvironment('COUNT', defaultValue: 1);
// Budget par graine (l'app utilise 120000 ms / 40 essais).
const _timeoutMs = int.fromEnvironment('TIMEOUT_MS', defaultValue: 20000);
const _retries = int.fromEnvironment('RETRIES', defaultValue: 8);

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
    var seed = baseSeed;
    var produced = 0;
    while (produced < _count && seed < baseSeed + _count * 40) {
      final grid = await gen.generate(
        TopologyConfig(
          rows: _rows,
          cols: _cols,
          seed: seed,
          backtrackTimeoutMs: _timeoutMs,
          maxRetries: _retries,
          maxDifficulty: _maxDiff == 0 ? null : _maxDiff,
        ),
      );
      if (grid == null) {
        seed++;
        continue;
      }
      final json = grid.toJson();
      json['seed'] = seed;
      json['maxDifficulty'] = _maxDiff == 0 ? null : _maxDiff;
      json['generatedAt'] = DateTime.now().toUtc().toIso8601String();
      final file = _count == 1
          ? File(_out)
          : File('$_out/grid_${_rows}x${_cols}_$seed.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      // ignore: avoid_print
      print(
        'OK ${grid.rows}x${grid.cols} seed=$seed '
        'clues=${grid.allClues.length} → ${file.path}',
      );
      produced++;
      seed++;
    }
    expect(produced, _count, reason: 'grilles produites : $produced/$_count');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
