/// Smoke test sur le fichier SQLite réel produit par tools/kb-builder/.
///
/// Vérifie : la KB se charge, contient ≥ 200 entrées, les requêtes solver
/// fonctionnent (lookup par longueur + lettre×position).
library;

import 'dart:io';

import 'package:chabaka/puzzle/kb/kb_repository.dart';
import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('KbRepositorySqflite — fichier réel', () {
    late KbRepositorySqflite repo;

    setUp(() async {
      final assetPath = '${Directory.current.path}/assets/kb/chabaka_kb.sqlite';
      expect(File(assetPath).existsSync(), isTrue,
          reason: 'Lance d\'abord `python3 tools/kb-builder/build_kb.py`');
      repo = await openKbRepositoryFromFile(
        assetPath,
        databaseFactoryOverride: databaseFactoryFfi,
      );
    });

    tearDown(() async {
      await repo.close();
    });

    test('contient au moins 200 entrées', () async {
      final n = await repo.countEntries();
      expect(n, greaterThanOrEqualTo(200));
    });

    test('findMatching par longueur fonctionne', () async {
      final entries = await repo.findMatching(length: 4, limit: 10);
      expect(entries, isNotEmpty);
      expect(entries.every((e) => e.length == 4), isTrue);
      // Chaque entrée a au moins un clue
      for (final e in entries) {
        expect(e.clues, isNotEmpty);
        expect(e.primaryClue, isNotNull);
      }
    });

    test('findMatching avec contrainte lettre×position', () async {
      // Mots de 4 lettres avec ا en position 1 : ex بلاد, الام, etc.
      final entries = await repo.findMatching(
        length: 4,
        constraints: [const LetterConstraint(position: 1, letter: 'ا')],
      );
      for (final e in entries) {
        expect(e.length, 4);
        final char = String.fromCharCode(e.word.runes.elementAt(1));
        expect(char, 'ا',
            reason: 'Lettre en position 1 de "${e.word}" devrait être ا');
      }
    });

    test('excludeIds filtre correctement', () async {
      final initial = await repo.findMatching(length: 3, limit: 5);
      expect(initial, isNotEmpty);
      final excluded = {initial.first.id};
      final filtered = await repo.findMatching(
        length: 3,
        excludeIds: excluded,
        limit: 50,
      );
      expect(filtered.any((e) => excluded.contains(e.id)), isFalse);
    });

    test('perf : 100 findMatching < 500ms (= < 5ms en moyenne)', () async {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await repo.findMatching(
          length: 4,
          constraints: [
            LetterConstraint(position: 0, letter: 'ا'),
          ],
          limit: 10,
        );
      }
      stopwatch.stop();
      // ignore: avoid_print
      print('100 findMatching : ${stopwatch.elapsedMilliseconds} ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}
