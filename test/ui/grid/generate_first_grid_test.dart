/// La génération en isolate (entrées préchargées + InMemoryKbRepository)
/// doit donner exactement la grille que donnerait le générateur branché sur
/// SQLite, sinon la grille du jour différerait selon le chemin pris.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/puzzle.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late KbRepositorySqflite kb;

  setUp(() async {
    kb = await openKbRepositoryFromFile(
      '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
      databaseFactoryOverride: databaseFactoryFfi,
    );
  });

  tearDown(() => kb.close());

  Future<Grid?> direct(TopologyConfig config, int seedAttempts) async {
    final generator = TrueInterleavedGenerator(kb: kb);
    for (var offset = 0; offset < seedAttempts; offset++) {
      final grid = await generator.generate(
        config.withSeed(config.seed + offset),
      );
      if (grid != null) return grid;
    }
    return null;
  }

  test('grille du jour : isolate = générateur direct', () async {
    final config = TopologyConfig.forDate(
      DateTime(2026, 10, 14),
      rows: 13,
      cols: 9,
    );
    final viaIsolate = await generateDailyGrid(kb, config);
    final viaSqlite = await direct(config, 100);
    expect(viaIsolate, isNotNull);
    expect(jsonEncode(viaIsolate!.toJson()), jsonEncode(viaSqlite!.toJson()));
  });

  test('partie rapide filtrée par difficulté : isolate = direct', () async {
    const config = TopologyConfig(
      rows: 10,
      cols: 7,
      seed: 4242,
      backtrackTimeoutMs: 30000,
      maxStepsPerAttempt: kDailyMaxStepsPerAttempt,
      maxDifficulty: 2,
    );
    final viaIsolate = await generateFirstGrid(kb, config, seedAttempts: 50);
    final viaSqlite = await direct(config, 50);
    expect(viaIsolate, isNotNull);
    expect(jsonEncode(viaIsolate!.toJson()), jsonEncode(viaSqlite!.toJson()));
  });
}
