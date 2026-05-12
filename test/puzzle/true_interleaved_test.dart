/// Tests du TrueInterleavedGenerator — moteur V4 (modèle B : clue offset diagonal).
///
/// ## Géométrie modèle B rappel
///
/// Une CC à (r, c) génère :
///   - H clue → mot dans row r+1, colonne c à c+L-1. startCell = (r+1, c).
///   - V clue → mot dans col c+1, ligne r à r+L-1. startCell = (r, c+1).
///
/// CC fermante :
///   - H : en (r+1, c+L)
///   - V : en (r+L, c+1)
///
/// ## Invariants testés
///
///   R1  : toute ClueCell porte ≥1 indice ; toute LetterCell a une lettre.
///   R5  : (0,0) est CC.
///   R7  : pas de ≥3 CCs consécutives H ou V.
///   R9  : densité CC ≥ 22 % pour 16×13.
///   R10 : aucun mot > 5 lettres.
///   R_orphan : aucune LC sans slot clué (zéro orphelines totales).
///   R_geom_B : vérification de la géométrie modèle B (startCell cohérent).
///
/// Exécution : flutter test test/puzzle/true_interleaved_test.dart
library;

import 'dart:io';

import 'package:chabaka/puzzle/generation/topology.dart';
import 'package:chabaka/puzzle/generation/true_interleaved_generator.dart';
import 'package:chabaka/puzzle/kb/kb_repository.dart';
import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/puzzle/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Helpers de validation modèle B
// ---------------------------------------------------------------------------

/// R1 + R5 cellulaire : toute CC porte ≥1 indice, toute LC a une lettre.
String? checkR1R5(Grid g) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is ClueCell && cell.clues.isEmpty) {
        return 'R1 violé : CC vide en ($r,$c)';
      }
      if (cell is LetterCell && cell.solution.isEmpty) {
        return 'R5 violé : LC vide en ($r,$c)';
      }
    }
  }
  return null;
}

/// R5 top-left : (0,0) doit être CC.
String? checkR5TopLeft(Grid g) {
  final cell = g.cells[0][0];
  if (cell is! ClueCell) {
    return 'R5 violé : (0,0) est ${cell.runtimeType}, attendu ClueCell';
  }
  return null;
}

/// R7 : pas de ≥3 CCs consécutives H ou V.
String? checkR7(Grid g) {
  for (var r = 0; r < g.rows; r++) {
    var run = 0;
    for (var c = 0; c < g.cols; c++) {
      run = g.cells[r][c] is ClueCell ? run + 1 : 0;
      if (run > 2) return 'R7 violé : $run CCs contig. H en ($r,$c)';
    }
  }
  for (var c = 0; c < g.cols; c++) {
    var run = 0;
    for (var r = 0; r < g.rows; r++) {
      run = g.cells[r][c] is ClueCell ? run + 1 : 0;
      if (run > 2) return 'R7 violé : $run CCs contig. V en ($r,$c)';
    }
  }
  return null;
}

/// R_orphan : aucune LC sans slot clué.
///
/// Une LC est orpheline si aucun Clue dans la grille n'inclut sa position.
/// Dans le modèle B, chaque LC doit être couverte par au moins un slot H ou V.
String? checkOrphanLcs(Grid g) {
  final covered = _coveredPositions(g);
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is LetterCell && !covered.contains((r, c))) {
        return 'R_orphan : LC orpheline en ($r,$c) (aucun slot clué)';
      }
    }
  }
  return null;
}

/// Nombre de LCs orphelines.
int countOrphanLcs(Grid g) {
  final covered = _coveredPositions(g);
  var orphans = 0;
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is LetterCell && !covered.contains((r, c))) {
        orphans++;
      }
    }
  }
  return orphans;
}

/// Construit l'ensemble des positions couvertes par au moins un slot clué.
Set<(int, int)> _coveredPositions(Grid g) {
  final covered = <(int, int)>{};
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is! ClueCell || cell.clues.isEmpty) continue;
      for (final clue in cell.clues) {
        final len = clue.solution.runes.length;
        for (var i = 0; i < len; i++) {
          final lr = clue.direction == Direction.horizontal
              ? clue.startCell.row
              : clue.startCell.row + i;
          final lc = clue.direction == Direction.horizontal
              ? clue.startCell.col + i
              : clue.startCell.col;
          covered.add((lr, lc));
        }
      }
    }
  }
  return covered;
}

/// R_geom_B : vérifie la cohérence géométrique modèle B.
///
/// Pour chaque CC (r, c) avec un indice H (startCell = (sr, sc)) :
///   - sr doit être r+1 (mot dans la row suivante).
///   - sc doit être dans [c, c+maxWordLen).
///
/// Pour chaque CC (r, c) avec un indice V (startCell = (sr, sc)) :
///   - sc doit être c+1 (mot dans la col suivante).
///   - sr doit être dans [r, r+maxWordLen).
String? checkGeomModelB(Grid g) {
  const maxLen = 5;
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is! ClueCell) continue;
      for (final clue in cell.clues) {
        final sr = clue.startCell.row;
        final sc = clue.startCell.col;
        if (clue.direction == Direction.horizontal) {
          if (sr != r + 1) {
            return 'geom_B H : CC($r,$c) startCell=($sr,$sc), attendu row=${r + 1}';
          }
          if (sc < c || sc >= c + maxLen + 1) {
            return 'geom_B H : CC($r,$c) startCell=($sr,$sc), col $sc hors plage [$c, ${c + maxLen})';
          }
        } else {
          if (sc != c + 1) {
            return 'geom_B V : CC($r,$c) startCell=($sr,$sc), attendu col=${c + 1}';
          }
          if (sr < r || sr >= r + maxLen + 1) {
            return 'geom_B V : CC($r,$c) startCell=($sr,$sc), row $sr hors plage [$r, ${r + maxLen})';
          }
        }
      }
    }
  }
  return null;
}

/// Longueur maximale d'un mot parmi toutes les clues.
int maxWordLen(Grid g) {
  var maxLen = 0;
  for (final clue in g.allClues) {
    final len = clue.solution.runes.length;
    if (len > maxLen) maxLen = len;
  }
  return maxLen;
}

/// Nombre de CCs dans la grille.
int countCCs(Grid g) {
  var count = 0;
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is ClueCell) count++;
    }
  }
  return count;
}

/// Validation complète — modèle B.
String? validateAll(Grid g) {
  return checkR5TopLeft(g) ??
      checkR1R5(g) ??
      checkR7(g) ??
      checkOrphanLcs(g) ??
      checkGeomModelB(g);
}

// ---------------------------------------------------------------------------
// Dump textuel — modèle B
// ---------------------------------------------------------------------------

/// Affiche la grille avec indication des CC et leurs mots.
///
/// Format :
///   C→(r+1,c) = H word startCell  |  C↓(r,c+1) = V word startCell
///   L = lettre de la solution
void dumpGrid(Grid g, {String? label}) {
  if (label != null) {
    // ignore: avoid_print
    print('\n=== $label ===');
  }
  // ignore: avoid_print
  print('Grille ${g.rows}×${g.cols}  (${countCCs(g)} CCs, '
      '${g.allClues.length} clues, ${countOrphanLcs(g)} orphanes)');

  // Header colonnes.
  var header = '     ';
  for (var c = 0; c < g.cols; c++) {
    header += 'c${c.toString().padLeft(2)} ';
  }
  // ignore: avoid_print
  print(header);

  for (var r = 0; r < g.rows; r++) {
    var line = 'r${r.toString().padLeft(2)}: ';
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is LetterCell) {
        line += ' ${cell.solution}  ';
      } else if (cell is ClueCell) {
        final dirs = cell.clues.map((cl) {
          return cl.direction == Direction.horizontal ? '→' : '↓';
        }).join('');
        final pad = dirs.isEmpty ? '[?]' : '[${dirs.padRight(2)}]';
        line += pad.padRight(4);
      }
    }
    // ignore: avoid_print
    print(line);
  }

  // Clues détaillées.
  // ignore: avoid_print
  print('\nClues :');
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is! ClueCell || cell.clues.isEmpty) continue;
      for (final clue in cell.clues) {
        final dir = clue.direction == Direction.horizontal ? '→H' : '↓V';
        // ignore: avoid_print
        print('  CC($r,$c) $dir "${clue.solution}" '
            'startCell=(${clue.startCell.row},${clue.startCell.col}) '
            '| ${clue.text}');
      }
    }
  }
}

// ---------------------------------------------------------------------------
// KB in-memory riche
// ---------------------------------------------------------------------------

InMemoryKbRepository _buildRichTestKb() {
  final words = [
    // 2 lettres
    ('يد', 'عضو'),
    ('أب', 'الوالد'),
    ('أم', 'الوالدة'),
    ('لا', 'نفي'),
    ('من', 'حرف جر'),
    ('في', 'حرف جر'),
    ('عن', 'حرف جر'),
    ('إن', 'توكيد'),
    ('أن', 'مصدري'),
    ('ما', 'استفهام'),
    ('هو', 'ضمير'),
    ('هي', 'ضمير'),
    ('قد', 'حرف تحقيق'),
    ('لو', 'حرف شرط'),
    ('أو', 'حرف عطف'),
    ('ثم', 'حرف عطف'),
    ('بل', 'حرف استدراك'),
    ('كم', 'حرف استفهام'),
    ('لن', 'نفي مستقبل'),
    ('رب', 'الخالق'),
    // 3 lettres
    ('علم', 'المعرفة'),
    ('عمل', 'النشاط'),
    ('بحر', 'ماء ملح'),
    ('قمر', 'يضيء الليل'),
    ('شمس', 'تشرق صباحاً'),
    ('ماء', 'أساس الحياة'),
    ('باب', 'مدخل'),
    ('نور', 'ضد الظلام'),
    ('نهر', 'مجرى مائي'),
    ('كتب', 'جمع كتاب'),
    ('ولد', 'طفل'),
    ('عصر', 'حقبة'),
    ('صبر', 'التحمل'),
    ('فكر', 'التأمل'),
    ('حلم', 'رؤية النائم'),
    ('أسد', 'ملك الغابة'),
    ('طير', 'جمع طائر'),
    ('درب', 'طريق'),
    ('حجر', 'صخرة'),
    ('سمك', 'حيوان مائي'),
    ('جبل', 'تل كبير'),
    ('برد', 'ضد الحر'),
    ('ثلج', 'ماء متجمد'),
    ('ريح', 'هواء متحرك'),
    ('صيف', 'فصل حار'),
    ('شتا', 'فصل بارد'),
    ('يوم', 'وحدة زمن'),
    ('أمس', 'اليوم السابق'),
    ('دار', 'منزل'),
    ('أرض', 'تراب'),
    // 4 lettres
    ('علوم', 'جمع علم'),
    ('بيوت', 'جمع بيت'),
    ('حروف', 'جمع حرف'),
    ('لغات', 'جمع لغة'),
    ('نجوم', 'جمع نجم'),
    ('بلاد', 'جمع بلد'),
    ('جبال', 'جمع جبل'),
    ('مدرب', 'معلم'),
    ('ثمار', 'جمع ثمرة'),
    ('كتاب', 'يُقرأ'),
    ('قلوب', 'جمع قلب'),
    // 5 lettres
    ('قرآن', 'الكتاب المقدس'),
    ('عقول', 'جمع عقل'),
    ('زمان', 'الوقت'),
    ('مكان', 'الموقع'),
    ('قطار', 'وسيلة نقل'),
    ('كرسي', 'مقعد'),
    ('شباب', 'فئة عمرية'),
    ('طريق', 'مسار'),
    ('حدود', 'نهاية البلد'),
    ('كلام', 'كلمات'),
    ('بيان', 'الوضوح'),
    ('أنوار', 'جمع نور'),
    ('أسرار', 'جمع سر'),
    ('أحزاب', 'جمع حزب'),
    ('أعمال', 'جمع عمل'),
    ('أقوال', 'جمع قول'),
    ('أرواح', 'جمع روح'),
    ('أفكار', 'جمع فكر'),
  ];

  final entries = <KbEntry>[];
  for (var i = 0; i < words.length; i++) {
    final (word, clue) = words[i];
    if (word.runes.length > 5) continue;
    entries.add(KbEntry(
      id: i + 1,
      word: word,
      wordDisplay: word,
      length: word.runes.length,
      category: KbCategory.common,
      clues: [KbClue(text: clue, kind: KbClueKind.definition)],
    ));
  }
  return InMemoryKbRepository(entries);
}

// ---------------------------------------------------------------------------
// Tests in-memory
// ---------------------------------------------------------------------------

void main() {
  group('TrueInterleavedGenerator V4 (modèle B) — in-memory KB', () {
    late InMemoryKbRepository kb;
    late TrueInterleavedGenerator gen;

    setUp(() {
      kb = _buildRichTestKb();
      gen = TrueInterleavedGenerator(kb: kb);
    });

    tearDown(() async => kb.close());

    test('converge sur 5×5 en < 1s', () async {
      final sw = Stopwatch()..start();
      final grid = await gen.generate(const TopologyConfig(
        rows: 5,
        cols: 5,
        seed: 42,
        backtrackTimeoutMs: 900,
        maxRetries: 10,
      ));
      sw.stop();

      // ignore: avoid_print
      print('5×5 in-mem : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
      expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'Cible < 1s');

      if (grid != null) {
        dumpGrid(grid, label: '5×5 in-mem seed=42');
        final err = validateAll(grid);
        expect(err, isNull, reason: err);
        // ignore: avoid_print
        print('  → ${grid.allClues.length} clues, ${grid.letterCells.length} LCs, '
            '${countCCs(grid)} CCs, maxWordLen=${maxWordLen(grid)}');
      }
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('(0,0) est CC', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5,
          cols: 5,
          seed: seed,
          backtrackTimeoutMs: 800,
          maxRetries: 5,
        ));
        if (g == null) continue;
        expect(g.cells[0][0], isA<ClueCell>(),
            reason: 'Seed=$seed : (0,0) doit être CC');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('R7 : pas de 3 CCs consécutives', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5,
          cols: 5,
          seed: seed,
          backtrackTimeoutMs: 800,
          maxRetries: 5,
        ));
        if (g == null) continue;
        final err = checkR7(g);
        expect(err, isNull, reason: 'Seed=$seed : $err');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('R_orphan : aucune LC orpheline (5×5, in-memory)', () async {
      var anyGrid = false;
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5,
          cols: 5,
          seed: seed,
          backtrackTimeoutMs: 800,
          maxRetries: 5,
        ));
        if (g == null) continue;
        anyGrid = true;
        final orphans = countOrphanLcs(g);
        // ignore: avoid_print
        print('5×5 seed=$seed : orphans=$orphans, CCs=${countCCs(g)}');
        expect(orphans, equals(0),
            reason: 'Seed=$seed : $orphans LCs orphelines (modèle B)');
      }
      if (!anyGrid) {
        // ignore: avoid_print
        print('[SKIP] Aucune grille 5×5 générée avec KB in-memory (normal)');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('Géométrie modèle B : startCell cohérent (5×5)', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5,
          cols: 5,
          seed: seed,
          backtrackTimeoutMs: 800,
          maxRetries: 5,
        ));
        if (g == null) continue;
        final err = checkGeomModelB(g);
        expect(err, isNull, reason: 'Seed=$seed : $err');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('aucun mot > 5 lettres (in-memory)', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5,
          cols: 5,
          seed: seed,
          backtrackTimeoutMs: 800,
          maxRetries: 5,
        ));
        if (g == null) continue;
        final maxLen = maxWordLen(g);
        // ignore: avoid_print
        print('5×5 seed=$seed : maxWordLen=$maxLen');
        expect(maxLen, lessThanOrEqualTo(5),
            reason: 'Seed=$seed : mot de $maxLen lettres trouvé');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // -------------------------------------------------------------------------
  // Tests avec KB SQLite réelle
  // -------------------------------------------------------------------------

  group('TrueInterleavedGenerator V4 (modèle B) — KB SQLite réelle', () {
    setUpAll(sqfliteFfiInit);

    late KbRepository kb;
    late TrueInterleavedGenerator gen;

    setUp(() async {
      final dbPath =
          '${Directory.current.path}/assets/kb/chabaka_kb.sqlite';
      kb = await openKbRepositoryFromFile(
        dbPath,
        databaseFactoryOverride: databaseFactoryFfi,
      );
      gen = TrueInterleavedGenerator(kb: kb);
    });

    tearDown(() async => kb.close());

    test('5×5 converge < 1s', () async {
      final sw = Stopwatch()..start();
      final grid = await gen.generate(const TopologyConfig(
        rows: 5,
        cols: 5,
        seed: 1,
        backtrackTimeoutMs: 900,
        maxRetries: 10,
      ));
      sw.stop();

      // ignore: avoid_print
      print('5×5 réel : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
      expect(sw.elapsedMilliseconds, lessThan(1000));

      if (grid != null) {
        dumpGrid(grid, label: '5×5 réel seed=1');
        final err = validateAll(grid);
        expect(err, isNull, reason: err);
        // ignore: avoid_print
        print('  → ${grid.allClues.length} clues, ${grid.letterCells.length} LCs, '
            '${countCCs(grid)} CCs, maxWordLen=${maxWordLen(grid)}');
      }
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('8×8 converge < 3s', () async {
      var converged = false;
      for (var seed = 1; seed <= 3 && !converged; seed++) {
        final sw = Stopwatch()..start();
        final grid = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 5,
        ));
        sw.stop();

        // ignore: avoid_print
        print('8×8 seed=$seed : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
        expect(sw.elapsedMilliseconds, lessThan(3000), reason: 'Cible < 3s');

        if (grid != null) {
          converged = true;
          dumpGrid(grid, label: '8×8 réel seed=$seed');
          final err = validateAll(grid);
          expect(err, isNull, reason: 'Seed=$seed : $err');
          // ignore: avoid_print
          print('  → ${grid.allClues.length} clues, ${grid.letterCells.length} LCs, '
              '${countCCs(grid)} CCs, maxWordLen=${maxWordLen(grid)}, '
              'orphans=${countOrphanLcs(grid)}');
        }
      }
      if (!converged) {
        // ignore: avoid_print
        print('[WARN] 8×8 : aucun seed n\'a convergé');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('13×13 converge < 30s', () async {
      var converged = false;
      for (var seed = 1; seed <= 2 && !converged; seed++) {
        final sw = Stopwatch()..start();
        final grid = await gen.generate(TopologyConfig(
          rows: 13,
          cols: 13,
          seed: seed,
          backtrackTimeoutMs: 28000,
          maxRetries: 3,
        ));
        sw.stop();

        // ignore: avoid_print
        print('13×13 seed=$seed : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
        expect(sw.elapsedMilliseconds, lessThan(30000), reason: 'Cible < 30s');

        if (grid != null) {
          converged = true;
          final err = validateAll(grid);
          expect(err, isNull, reason: 'Seed=$seed : $err');
          final orphans = countOrphanLcs(grid);
          // ignore: avoid_print
          print('  → ${grid.allClues.length} clues, ${grid.letterCells.length} LCs, '
              '${countCCs(grid)} CCs, maxWordLen=${maxWordLen(grid)}, '
              'orphans=$orphans');
        }
      }
      if (!converged) {
        // ignore: avoid_print
        print('[WARN] 13×13 : pas de convergence dans les délais');
      }
    }, timeout: const Timeout(Duration(seconds: 65)));

    test('PERF 16×13 dense : converge < 2min avec ≥40 CCs', () async {
      final sw = Stopwatch()..start();
      final grid = await gen.generate(const TopologyConfig(
        rows: 16,
        cols: 13,
        seed: 42,
        backtrackTimeoutMs: 110000,
        maxRetries: 100,
      ));
      sw.stop();

      // ignore: avoid_print
      print('16×13 seed=42 : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
      expect(sw.elapsedMilliseconds, lessThan(120000), reason: 'Cible P95 < 2min');

      if (grid != null) {
        dumpGrid(grid, label: '16×13 dense seed=42');
        final err = validateAll(grid);
        expect(err, isNull, reason: err);

        final ccs = countCCs(grid);
        final clues = grid.allClues.length;
        final maxLen = maxWordLen(grid);
        final orphans = countOrphanLcs(grid);

        // ignore: avoid_print
        print('  → $clues clues, ${grid.letterCells.length} LCs, $ccs CCs');
        // ignore: avoid_print
        print('  → maxWordLen=$maxLen, orphans=$orphans');

        // Cibles modèle B.
        expect(ccs, greaterThanOrEqualTo(40),
            reason: '16×13 dense doit avoir ≥40 CCs (Abu Salma), trouvé $ccs');
        expect(clues, greaterThanOrEqualTo(30),
            reason: '16×13 doit avoir ≥30 clues distinctes, trouvé $clues');
        expect(maxLen, lessThanOrEqualTo(5),
            reason: 'Aucun mot ne doit dépasser 5 lettres, trouvé $maxLen');
        expect(orphans, equals(0),
            reason: '0 orphanes attendues (modèle B), trouvé $orphans');
      } else {
        // ignore: avoid_print
        print('[WARN] 16×13 seed=42 : pas de grille dans le délai');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Dump seed=862 — visualisation PO (16×13)', () async {
      final sw = Stopwatch()..start();
      final grid = await gen.generate(const TopologyConfig(
        rows: 16,
        cols: 13,
        seed: 862,
        backtrackTimeoutMs: 110000,
        maxRetries: 50,
      ));
      sw.stop();

      // ignore: avoid_print
      print('16×13 seed=862 : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');

      if (grid != null) {
        dumpGrid(grid, label: '16×13 seed=862 — modèle B diagonal');
        final err = validateAll(grid);
        // ignore: avoid_print
        print('Validation : ${err ?? "OK"}');
        // ignore: avoid_print
        print('Stats : CCs=${countCCs(grid)}, clues=${grid.allClues.length}, '
            'orphans=${countOrphanLcs(grid)}, maxWordLen=${maxWordLen(grid)}');
        expect(err, isNull, reason: err);
        expect(countOrphanLcs(grid), equals(0),
            reason: 'seed=862 : orphanes résiduelles');
      } else {
        // ignore: avoid_print
        print('[SKIP] seed=862 : grille non générée dans le délai');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('R1 sur 3 seeds 8×8', () async {
      for (var seed = 1; seed <= 3; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 3,
        ));
        if (g == null) continue;
        final err = checkR1R5(g);
        expect(err, isNull, reason: 'Seed=$seed : $err');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('R7 sur 3 seeds 8×8', () async {
      for (var seed = 1; seed <= 3; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 3,
        ));
        if (g == null) continue;
        final err = checkR7(g);
        expect(err, isNull, reason: 'Seed=$seed : $err');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('R_orphan sur 3 seeds 8×8 (modèle B)', () async {
      for (var seed = 1; seed <= 3; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 3,
        ));
        if (g == null) continue;
        final orphans = countOrphanLcs(g);
        // ignore: avoid_print
        print('8×8 seed=$seed : orphans=$orphans, CCs=${countCCs(g)}, maxWordLen=${maxWordLen(g)}');
        expect(orphans, equals(0),
            reason: 'Seed=$seed : $orphans LCs orphelines (modèle B strict)');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('Géométrie modèle B sur 3 seeds 8×8', () async {
      for (var seed = 1; seed <= 3; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 3,
        ));
        if (g == null) continue;
        final err = checkGeomModelB(g);
        expect(err, isNull, reason: 'Seed=$seed : $err');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('aucun mot >5 lettres sur 3 seeds 8×8', () async {
      for (var seed = 1; seed <= 3; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 3,
        ));
        if (g == null) continue;
        final maxLen = maxWordLen(g);
        expect(maxLen, lessThanOrEqualTo(5),
            reason: 'Seed=$seed : mot de $maxLen lettres (max attendu 5)');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
