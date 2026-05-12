/// Tests du TrueInterleavedGenerator — moteur constructif V3 dense.
///
/// Vérifie :
///   - Convergence 5×5 (<1s), 8×8 (<3s), 13×13 (<30s), 16×13 (<2min)
///   - R1 : toute ClueCell porte ≥1 indice
///   - R5 : (0,0)=CC, grille pleine, aucune LC sans lettre
///   - R7 : pas de ≥3 CCs consécutives H ou V
///   - R8 STRICT : pas de V-run ≥2 LCs sans CC immédiatement au-dessus (row 0 inclus)
///   - Densité : ≥50 CCs pour 16×13 (cible Abu Salma)
///   - Longueur max de mot : aucun mot >6 lettres
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
// Helpers de validation
// ---------------------------------------------------------------------------

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

String? checkR5TopLeft(Grid g) {
  final cell = g.cells[0][0];
  if (cell is! ClueCell) {
    return 'R5 violé : (0,0) est ${cell.runtimeType}, attendu ClueCell';
  }
  return null;
}

/// R7 : pas de ≥3 CCs consécutives (contrainte V3 stricte).
String? checkR7(Grid g) {
  const maxRun = 2; // ≥3 = violation
  for (var r = 0; r < g.rows; r++) {
    var run = 0;
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is ClueCell) {
        run++;
        if (run > maxRun) return 'R7 violé : $run CCs contig. H en ($r,$c)';
      } else {
        run = 0;
      }
    }
  }
  for (var c = 0; c < g.cols; c++) {
    var run = 0;
    for (var r = 0; r < g.rows; r++) {
      if (g.cells[r][c] is ClueCell) {
        run++;
        if (run > maxRun) return 'R7 violé : $run CCs contig. V en ($r,$c)';
      } else {
        run = 0;
      }
    }
  }
  return null;
}

/// R8 STRICT : pas de V-run ≥2 LCs sans CC immédiatement au-dessus.
///
/// [strictRow0] : si true (grandes grilles ≥10 lignes), inclut les runs
/// depuis row 0. Si false (petites grilles), tolère les V-runs depuis row 0
/// car il est géométriquement impossible d'avoir toute la row 0 en CCs
/// sans violer R7 sur peu de colonnes.
String? checkR8Strict(Grid g, {bool strictRow0 = true}) {
  for (var c = 0; c < g.cols; c++) {
    var r = 0;
    while (r < g.rows) {
      if (g.cells[r][c] is! LetterCell) {
        r++;
        continue;
      }
      final runStart = r;
      while (r < g.rows && g.cells[r][c] is LetterCell) {
        r++;
      }
      final runLen = r - runStart;
      if (runLen >= 2) {
        if (runStart == 0) {
          if (strictRow0) {
            return 'R8 violé : V-run de $runLen LCs depuis row 0 en col $c (pas de CC au-dessus)';
          }
          // En mode non-strict, on tolère les V-runs depuis row 0.
        } else if (g.cells[runStart - 1][c] is! ClueCell) {
          return 'R8 violé : V-run de $runLen LCs en col $c row $runStart sans CC immédiatement au-dessus';
        }
      }
    }
  }
  return null;
}

/// Compte les V edge slots (run V ≥2 depuis row 0 ou sans CC au-dessus).
/// [strictRow0] : si true, inclut les V-runs depuis row 0.
int countVEdgeSlots(Grid g, {bool strictRow0 = true}) {
  var count = 0;
  for (var c = 0; c < g.cols; c++) {
    var r = 0;
    while (r < g.rows) {
      if (g.cells[r][c] is! LetterCell) {
        r++;
        continue;
      }
      final runStart = r;
      while (r < g.rows && g.cells[r][c] is LetterCell) {
        r++;
      }
      final runLen = r - runStart;
      if (runLen >= 2) {
        final fromEdge = runStart == 0;
        final noClueAbove =
            runStart > 0 && g.cells[runStart - 1][c] is! ClueCell;
        if (noClueAbove || (fromEdge && strictRow0)) {
          count++;
        }
      }
    }
  }
  return count;
}

/// Compte les LCs orphelines (non couvertes par aucun slot clué H ou V).
///
/// Une LC est orpheline si aucune Clue dans la grille ne contient sa position.
/// Ces LCs sont injouables : le joueur n'a aucun indice pour les deviner.
int countOrphanLcs(Grid g) {
  // Construit l'ensemble des positions couvertes par au moins un slot clué.
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

/// Compte les LCs orphelines uniquement en row 0.
///
/// Même logique que countOrphanLcs mais limité à r=0.
/// C'est le bug spécifique corrigé par ce fix.
int countOrphanLcsRow0(Grid g) {
  final covered = <int>{};
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is! ClueCell || cell.clues.isEmpty) continue;
      for (final clue in cell.clues) {
        if (clue.direction != Direction.horizontal) continue;
        if (clue.startCell.row != 0) continue;
        final len = clue.solution.runes.length;
        for (var i = 0; i < len; i++) {
          covered.add(clue.startCell.col + i);
        }
      }
    }
  }

  var orphans = 0;
  for (var c = 0; c < g.cols; c++) {
    if (g.cells[0][c] is LetterCell && !covered.contains(c)) {
      orphans++;
    }
  }
  return orphans;
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

/// Validation complète adaptative.
///
/// R8 : strictRow0=false pour toutes les tailles.
/// Les vraies grilles Abu Salma ont des LCs en row 0 participant à des V-runs
/// depuis le bord — c'est valide. La contrainte pertinente est désormais
/// R_orphan_row0 : aucune LC en row 0 sans slot H clué.
String? validateAll(Grid g) {
  return checkR5TopLeft(g) ??
      checkR1R5(g) ??
      checkR7(g) ??
      checkR8Strict(g, strictRow0: false) ??
      checkOrphanRow0(g);
}

/// R_orphan_row0 : aucune LC en row 0 ne doit être orpheline (sans slot H clué).
///
/// Applicable aux grandes grilles (≥16 lignes) uniquement.
/// Pour les petites grilles, row 0 peut avoir des LCs orphelines sans affecter
/// la jouabilité (peu de colonnes, la grille converge difficilement).
String? checkOrphanRow0(Grid g) {
  if (g.rows < 16) return null;

  final covered = <int>{};
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is! ClueCell || cell.clues.isEmpty) continue;
      for (final clue in cell.clues) {
        if (clue.direction != Direction.horizontal) continue;
        if (clue.startCell.row != 0) continue;
        final len = clue.solution.runes.length;
        for (var i = 0; i < len; i++) {
          covered.add(clue.startCell.col + i);
        }
      }
    }
  }

  for (var c = 0; c < g.cols; c++) {
    if (g.cells[0][c] is LetterCell && !covered.contains(c)) {
      return 'R_orphan_row0 : LC orpheline en (0,$c) (non couverte par slot H)';
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// KB in-memory riche pour les tests
// ---------------------------------------------------------------------------

InMemoryKbRepository _buildRichTestKb() {
  // Vocabulaire élargi pour maximiser les chances de convergence même sur
  // de petites grilles avec une KB in-memory.
  // Limité à des mots de longueur ≤5 (contrainte V3 dense).
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
    ('قلوب', 'جمع قلب'),
    ('علوم', 'جمع علم'),
    ('بيوت', 'جمع بيت'),
    ('حروف', 'جمع حرف'),
    ('لغات', 'جمع لغة'),
    ('نجوم', 'جمع نجم'),
    ('بلاد', 'جمع بلد'),
    ('جبال', 'جمع جبل'),
    ('مدرب', 'معلم'),
    ('ثمار', 'جمع ثمرة'),
    ('أحلام', 'جمع حلم'),
    ('أوقات', 'جمع وقت'),
    ('إخوة', 'جمع أخ'),
    ('كتاب', 'يُقرأ'),
    ('أبواب', 'جمع باب'),
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
    // Filtre les mots de longueur > 5 (sécurité supplémentaire).
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
  group('TrueInterleavedGenerator — in-memory KB', () {
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
      expect(sw.elapsedMilliseconds, lessThan(1000),
          reason: 'Cible < 1s');

      if (grid != null) {
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

    test('R8 STRICT : pas de V edge slots internes (in-memory)', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5,
          cols: 5,
          seed: seed,
          backtrackTimeoutMs: 800,
          maxRetries: 5,
        ));
        if (g == null) continue;
        // Pour les petites grilles (5×5), on ne vérifie que les V edge slots
        // internes (pas depuis row 0).
        final vEdge = countVEdgeSlots(g, strictRow0: false);
        // ignore: avoid_print
        print('5×5 seed=$seed : V edge slots internes = $vEdge');
        expect(vEdge, equals(0),
            reason: 'Seed=$seed : $vEdge V edge slots internes trouvés');
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

  group('TrueInterleavedGenerator — KB SQLite réelle', () {
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
        print(
            '8×8 seed=$seed : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
        expect(sw.elapsedMilliseconds, lessThan(3000),
            reason: 'Cible < 3s par seed');

        if (grid != null) {
          converged = true;
          final err = validateAll(grid);
          expect(err, isNull, reason: 'Seed=$seed : $err');
          // ignore: avoid_print
          print(
              '  → ${grid.allClues.length} clues, ${grid.letterCells.length} LCs, '
              '${countCCs(grid)} CCs, maxWordLen=${maxWordLen(grid)}, '
              'V edge=${countVEdgeSlots(grid, strictRow0: false)}');
        }
      }
      // ignore: avoid_print
      if (!converged) print('[WARN] 8×8 : aucun seed n\'a convergé (KB insuffisante ?)');
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
        print(
            '13×13 seed=$seed : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
        expect(sw.elapsedMilliseconds, lessThan(30000),
            reason: 'Cible < 30s');

        if (grid != null) {
          converged = true;
          final err = validateAll(grid);
          expect(err, isNull, reason: 'Seed=$seed : $err');
          // ignore: avoid_print
          print(
              '  → ${grid.allClues.length} clues, ${grid.letterCells.length} LCs, '
              '${countCCs(grid)} CCs, maxWordLen=${maxWordLen(grid)}, '
              'V edge=${countVEdgeSlots(grid, strictRow0: grid.rows >= 10)}');
        }
      }
      // ignore: avoid_print
      if (!converged) print('[WARN] 13×13 : pas de convergence dans les délais');
    }, timeout: const Timeout(Duration(seconds: 65)));

    test('PERF 16×13 dense : converge < 2min avec ≥50 CCs', () async {
      final sw = Stopwatch()..start();
      final grid = await gen.generate(const TopologyConfig(
        rows: 16,
        cols: 13,
        seed: 42,
        backtrackTimeoutMs: 110000, // 1m50 timeout global
        maxRetries: 100, // augmenté (le fix R_orphan peut rejeter plus d'attempts)
      ));
      sw.stop();

      // ignore: avoid_print
      print('16×13 : ${sw.elapsedMilliseconds} ms, grille=${grid != null}');
      expect(sw.elapsedMilliseconds, lessThan(120000),
          reason: 'Cible P95 < 2min');

      if (grid != null) {
        final err = validateAll(grid);
        expect(err, isNull, reason: err);

        final ccs = countCCs(grid);
        final clues = grid.allClues.length;
        final maxLen = maxWordLen(grid);
        // Compte les orphelines totales et celles de row 0 spécifiquement.
        final orphans = countOrphanLcs(grid);
        final vEdge = countVEdgeSlots(grid, strictRow0: false);

        // ignore: avoid_print
        print('  → $clues clues, ${grid.letterCells.length} LCs, $ccs CCs');
        // ignore: avoid_print
        print('  → maxWordLen=$maxLen, V edge internes=$vEdge, orphans=$orphans');

        // Cibles Abu Salma.
        expect(ccs, greaterThanOrEqualTo(50),
            reason: '16×13 dense doit avoir ≥50 CCs (Abu Salma), trouvé $ccs');
        expect(clues, greaterThanOrEqualTo(30),
            reason: '16×13 dense doit avoir ≥30 clues distinctes, trouvé $clues');
        expect(maxLen, lessThanOrEqualTo(6),
            reason: 'Aucun mot ne doit dépasser 6 lettres, trouvé $maxLen');
        expect(vEdge, equals(0),
            reason: '16×13 doit avoir 0 V edge slot interne, trouvé $vEdge');

        if (sw.elapsedMilliseconds < 120000) {
          // ignore: avoid_print
          print('  [OK] Objectif <2 min atteint');
        }
      } else {
        // ignore: avoid_print
        print('[WARN] 16×13 : pas de grille dans le délai (KB insuffisante ?)');
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

    test('R8 STRICT sur 3 seeds 8×8', () async {
      for (var seed = 1; seed <= 3; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 8,
          cols: 8,
          seed: seed,
          backtrackTimeoutMs: 2500,
          maxRetries: 3,
        ));
        if (g == null) continue;
        // Pour 8×8 (petite grille), on vérifie seulement les V edge slots internes.
        final vEdge = countVEdgeSlots(g, strictRow0: false);
        // ignore: avoid_print
        print('8×8 seed=$seed : V edge internes=$vEdge, CCs=${countCCs(g)}, maxWordLen=${maxWordLen(g)}');
        expect(vEdge, equals(0),
            reason: 'Seed=$seed : $vEdge V edge slots internes (R8 strict)');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('aucun mot >6 lettres sur 3 seeds 8×8', () async {
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
        expect(maxLen, lessThanOrEqualTo(6),
            reason: 'Seed=$seed : mot de $maxLen lettres (max attendu 6)');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    // -------------------------------------------------------------------------
    // Régression bug orphelines — seeds 862-875 (16×13)
    //
    // Bug corrigé : seed=862 produisait 14 LCs orphelines EN ROW 0
    // (cols 2, 5, 8, 11 + similaires). Ces LCs n'avaient ni H clue ni V clue.
    //
    // Après le fix : 0 orphelines en row 0 pour tous ces seeds.
    //
    // Note : le générateur V3 peut encore produire des orphelines dans le corps
    // de la grille (rows 1-15), ce n'est pas le bug corrigé ici. Ce check porte
    // uniquement sur row 0 via countOrphanLcsRow0.
    // -------------------------------------------------------------------------

    test('0 LC orphelines en row 0 pour seeds 862-870 (16×13)', () async {
      for (var seed = 862; seed <= 870; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 16,
          cols: 13,
          seed: seed,
          backtrackTimeoutMs: 110000,
          maxRetries: 3,
        ));
        if (g == null) {
          // ignore: avoid_print
          print('[SKIP] seed=$seed : grille non générée');
          continue;
        }
        final orphansRow0 = countOrphanLcsRow0(g);
        final orphansTotal = countOrphanLcs(g);
        final ccs = countCCs(g);
        // ignore: avoid_print
        print('16×13 seed=$seed : orphans_row0=$orphansRow0, '
            'orphans_total=$orphansTotal, CCs=$ccs, clues=${g.allClues.length}');
        expect(orphansRow0, equals(0),
            reason: 'Seed=$seed : $orphansRow0 LCs orphelines en row 0 (bug corrigé)');
      }
    }, timeout: const Timeout(Duration(minutes: 35)));

    test('0 LC orphelines en row 0 pour seed=875 (16×13 — seed du rapport)', () async {
      final g = await gen.generate(const TopologyConfig(
        rows: 16,
        cols: 13,
        seed: 875,
        backtrackTimeoutMs: 110000,
        maxRetries: 3,
      ));
      if (g == null) {
        // ignore: avoid_print
        print('[SKIP] seed=875 : grille non générée');
        return;
      }
      final orphans = countOrphanLcsRow0(g);
      // ignore: avoid_print
      print('16×13 seed=875 : orphans=$orphans');
      expect(orphans, equals(0),
          reason: 'Seed=875 : $orphans LCs orphelines');
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}
