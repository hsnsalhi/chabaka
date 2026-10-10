/// Implémentation [KbRepository] basée sur SQLite via le package `sqflite`.
///
/// La base est embarquée en asset `assets/kb/chabaka_kb.sqlite` et copiée
/// vers le répertoire DB de l'app, en lecture seule. La copie est refaite
/// à chaque fois que l'asset change (taille différente), pour qu'une mise à
/// jour de l'app apporte bien la nouvelle base.
///
/// Schéma : cf. `tools/kb-builder/build_kb.py` et `docs/V1-MVP-R4-spec.md` § 1.2.

library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'kb_repository.dart';

const String _kbAssetPath = 'assets/kb/chabaka_kb.sqlite';
const String _kbFileName = 'chabaka_kb.sqlite';

/// Ouvre la base depuis l'asset (copie au 1er lancement ou après mise à jour).
///
/// [databaseFactoryOverride] permet de fournir un `databaseFactory` custom
/// (ex : `databaseFactoryFfi` pour tests unitaires desktop).
Future<KbRepositorySqflite> openKbRepositorySqflite({
  DatabaseFactory? databaseFactoryOverride,
}) async {
  final factory = databaseFactoryOverride ?? databaseFactory;
  final dbDir = await factory.getDatabasesPath();
  final dbPath = p.join(dbDir, _kbFileName);

  final ByteData bytes = await rootBundle.load(_kbAssetPath);
  final file = File(dbPath);
  final needsCopy =
      !await file.exists() || await file.length() != bytes.lengthInBytes;
  if (needsCopy) {
    await Directory(dbDir).create(recursive: true);
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  final db = await factory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true),
  );
  return KbRepositorySqflite(db);
}

/// Variante pour tests : prend un chemin de fichier déjà existant
/// (utile pour pointer directement vers `assets/kb/chabaka_kb.sqlite`
/// sans passer par rootBundle).
Future<KbRepositorySqflite> openKbRepositoryFromFile(
  String filePath, {
  DatabaseFactory? databaseFactoryOverride,
}) async {
  final factory = databaseFactoryOverride ?? databaseFactory;
  final db = await factory.openDatabase(
    filePath,
    options: OpenDatabaseOptions(readOnly: true),
  );
  return KbRepositorySqflite(db);
}

class KbRepositorySqflite implements KbRepository {
  final Database _db;
  bool _closed = false;

  KbRepositorySqflite(this._db);

  @override
  Future<List<KbEntry>> findMatching({
    required int length,
    List<LetterConstraint> constraints = const [],
    Set<int> excludeIds = const {},
    Set<String>? categories,
    int limit = 50,
  }) async {
    _assertOpen();

    final whereClauses = <String>['e.length = ?'];
    final args = <Object?>[length];

    for (final c in constraints) {
      whereClauses.add(
        'e.id IN (SELECT entry_id FROM letter_index '
        'WHERE length = ? AND position = ? AND letter = ?)',
      );
      args.addAll([length, c.position, c.letter]);
    }

    if (excludeIds.isNotEmpty) {
      final placeholders = List.filled(excludeIds.length, '?').join(',');
      whereClauses.add('e.id NOT IN ($placeholders)');
      args.addAll(excludeIds);
    }

    if (categories != null && categories.isNotEmpty) {
      final placeholders = List.filled(categories.length, '?').join(',');
      whereClauses.add('e.category IN ($placeholders)');
      args.addAll(categories);
    }

    final sql =
        'SELECT e.id, e.word, e.word_display, e.length, e.category, '
        'e.difficulty, e.source, e.reviewed '
        'FROM entries e '
        'WHERE ${whereClauses.join(' AND ')} '
        'LIMIT ?';
    args.add(limit);

    final rows = await _db.rawQuery(sql, args);
    if (rows.isEmpty) return const [];

    final ids = rows.map((r) => r['id'] as int).toList();
    final cluesById = await _loadClues(ids);

    return [
      for (final row in rows)
        KbEntry(
          id: row['id'] as int,
          word: row['word'] as String,
          wordDisplay: row['word_display'] as String,
          length: row['length'] as int,
          category: KbCategory.fromString(row['category'] as String),
          difficulty: row['difficulty'] as int,
          source: row['source'] as String,
          reviewed: row['reviewed'] as int,
          clues: cluesById[row['id'] as int] ?? const [],
        ),
    ];
  }

  @override
  Future<int> countEntries() async {
    _assertOpen();
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM entries');
    return (rows.first['n'] as int);
  }

  @override
  Future<int> countMatchingCategories(Set<String> categories) async {
    _assertOpen();
    if (categories.isEmpty) return countEntries();
    final placeholders = List.filled(categories.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM entries WHERE category IN ($placeholders)',
      categories.toList(),
    );
    return (rows.first['n'] as int);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }

  Future<Map<int, List<KbClue>>> _loadClues(List<int> entryIds) async {
    if (entryIds.isEmpty) return const {};
    final placeholders = List.filled(entryIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT entry_id, text, kind, priority FROM clues '
      'WHERE entry_id IN ($placeholders) '
      'ORDER BY entry_id, priority',
      entryIds,
    );
    final byId = <int, List<KbClue>>{};
    for (final r in rows) {
      final id = r['entry_id'] as int;
      (byId[id] ??= <KbClue>[]).add(
        KbClue(
          text: r['text'] as String,
          kind: KbClueKind.fromString(r['kind'] as String),
          priority: r['priority'] as int,
        ),
      );
    }
    return byId;
  }

  void _assertOpen() {
    if (_closed) throw StateError('KbRepository est fermé');
  }
}
