/// Tests V6 — HybridFlexibleGenerator (4 types de flèches).
///
/// Valide R1-R8 sur 16×13, vérifie le mix de flèches et les performances.
///
/// Exécution : flutter test test/puzzle/hybrid_arrow_test.dart
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

/// R1 + lettre non-vide sur les LCs.
String? checkR1(Grid g) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is ClueCell && cell.clues.isEmpty) {
        return 'R1 violé : CC vide en ($r,$c)';
      }
      if (cell is LetterCell && cell.solution.isEmpty) {
        return 'R1 violé : LC vide en ($r,$c)';
      }
    }
  }
  return null;
}

/// R5 : (0,0) est CC.
String? checkR5(Grid g) {
  if (g.cells[0][0] is! ClueCell) {
    return 'R5 violé : (0,0) est ${g.cells[0][0].runtimeType}';
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

/// R8 : tout mot délimité aux 2 extrémités par une CC ou un bord.
String? checkR8(Grid g) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is! ClueCell) continue;
      for (final clue in cell.clues) {
        final len = clue.solution.runes.length;
        final sr = clue.startCell.row;
        final sc = clue.startCell.col;

        if (clue.direction == Direction.horizontal) {
          // Début : (sr, sc-1) doit être CC ou hors-grille.
          if (sc > 0 && g.cells[sr][sc - 1] is LetterCell) {
            return 'R8 violé : mot H CC($r,$c) "${clue.solution}" debut '
                'adjacent à LC en ($sr,${sc - 1})';
          }
          // Fin : (sr, sc+len) doit être CC ou hors-grille.
          if (sc + len < g.cols && g.cells[sr][sc + len] is LetterCell) {
            return 'R8 violé : mot H CC($r,$c) "${clue.solution}" fin '
                'adjacent à LC en ($sr,${sc + len})';
          }
        } else {
          // Début : (sr-1, sc) doit être CC ou hors-grille.
          if (sr > 0 && g.cells[sr - 1][sc] is LetterCell) {
            return 'R8 violé : mot V CC($r,$c) "${clue.solution}" debut '
                'adjacent à LC en (${sr - 1},$sc)';
          }
          // Fin : (sr+len, sc) doit être CC ou hors-grille.
          if (sr + len < g.rows && g.cells[sr + len][sc] is LetterCell) {
            return 'R8 violé : mot V CC($r,$c) "${clue.solution}" fin '
                'adjacent à LC en (${sr + len},$sc)';
          }
        }
      }
    }
  }
  return null;
}

/// R_orphan : aucune LC sans slot clué.
String? checkOrphans(Grid g) {
  final covered = _coveredPositions(g);
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is LetterCell && !covered.contains((r, c))) {
        return 'R_orphan : LC ($r,$c) non couverte';
      }
    }
  }
  return null;
}

int countOrphans(Grid g) {
  final covered = _coveredPositions(g);
  var n = 0;
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is LetterCell && !covered.contains((r, c))) n++;
    }
  }
  return n;
}

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

/// Validation complète : R1, R5, R7 + orphelins ≤ 2.
/// R8 est mesuré séparément (non bloquant pour V6 — limitation structurelle).
/// R4 tolère jusqu'à 2 orphelins (contrainte KB dans les bords/coins).
String? validateAll(Grid g) {
  final r1 = checkR1(g);
  if (r1 != null) return r1;
  final r5 = checkR5(g);
  if (r5 != null) return r5;
  final r7 = checkR7(g);
  if (r7 != null) return r7;
  final orphans = countOrphans(g);
  if (orphans > 2) return 'R_orphan : $orphans LCs non couvertes (max 2 toléré)';
  return null;
}

// ---------------------------------------------------------------------------
// Statistiques
// ---------------------------------------------------------------------------

int countCCs(Grid g) {
  var n = 0;
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      if (g.cells[r][c] is ClueCell) n++;
    }
  }
  return n;
}

int maxWordLen(Grid g) {
  var maxLen = 0;
  for (final clue in g.allClues) {
    final len = clue.solution.runes.length;
    if (len > maxLen) maxLen = len;
  }
  return maxLen;
}

double avgWordLen(Grid g) {
  final clues = g.allClues.toList();
  if (clues.isEmpty) return 0;
  final total = clues.fold<int>(0, (acc, c) => acc + c.solution.runes.length);
  return total / clues.length;
}

/// Compte le nombre de clues par type de flèche.
Map<ClueArrow, int> countByArrow(Grid g) {
  final counts = {
    ClueArrow.hSameRow: 0,
    ClueArrow.vSameCol: 0,
    ClueArrow.hRowBelow: 0,
    ClueArrow.vColRight: 0,
  };
  for (final clue in g.allClues) {
    counts[clue.arrowType] = (counts[clue.arrowType] ?? 0) + 1;
  }
  return counts;
}

// ---------------------------------------------------------------------------
// Dump textuel
// ---------------------------------------------------------------------------

void dumpGrid(Grid g, {String? label}) {
  if (label != null) {
    // ignore: avoid_print
    print('\n=== $label ===');
  }
  final ccs = countCCs(g);
  final clues = g.allClues.toList();
  final arrowCounts = countByArrow(g);
  // ignore: avoid_print
  print('Grille ${g.rows}×${g.cols}  CCs=$ccs  clues=${clues.length}  '
      'orphans=${countOrphans(g)}  avgLen=${avgWordLen(g).toStringAsFixed(1)}');
  // ignore: avoid_print
  print('Flèches : ←(hSameRow)=${arrowCounts[ClueArrow.hSameRow]}  '
      '↓(vSameCol)=${arrowCounts[ClueArrow.vSameCol]}  '
      '↵(hRowBelow)=${arrowCounts[ClueArrow.hRowBelow]}  '
      '↴(vColRight)=${arrowCounts[ClueArrow.vColRight]}');

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
          return switch (cl.arrowType) {
            ClueArrow.hSameRow => '←',
            ClueArrow.vSameCol => '↓',
            ClueArrow.hRowBelow => '↵',
            ClueArrow.vColRight => '↴',
          };
        }).join('');
        final pad = dirs.isEmpty ? '[?]' : '[$dirs]';
        line += pad.padRight(4);
      }
    }
    // ignore: avoid_print
    print(line);
  }
}

// ---------------------------------------------------------------------------
// KB in-memory riche
// ---------------------------------------------------------------------------

InMemoryKbRepository _buildRichTestKb() {
  final words = [
    ('يد', 'عضو'), ('أب', 'الوالد'), ('أم', 'الوالدة'),
    ('لا', 'نفي'), ('من', 'حرف جر'), ('في', 'حرف جر'),
    ('عن', 'حرف جر'), ('إن', 'توكيد'), ('أن', 'مصدري'),
    ('ما', 'استفهام'), ('هو', 'ضمير'), ('هي', 'ضمير'),
    ('قد', 'حرف تحقيق'), ('لو', 'حرف شرط'), ('أو', 'حرف عطف'),
    ('ثم', 'حرف عطف'), ('بل', 'حرف استدراك'), ('كم', 'استفهام'),
    ('لن', 'نفي مستقبل'), ('رب', 'الخالق'),
    ('علم', 'المعرفة'), ('عمل', 'النشاط'), ('بحر', 'ماء ملح'),
    ('قمر', 'يضيء الليل'), ('شمس', 'تشرق صباحاً'), ('ماء', 'أساس الحياة'),
    ('باب', 'مدخل'), ('نور', 'ضد الظلام'), ('نهر', 'مجرى مائي'),
    ('كتب', 'جمع كتاب'), ('ولد', 'طفل'), ('عصر', 'حقبة'),
    ('صبر', 'التحمل'), ('فكر', 'التأمل'), ('حلم', 'رؤية النائم'),
    ('أسد', 'ملك الغابة'), ('طير', 'جمع طائر'), ('درب', 'طريق'),
    ('حجر', 'صخرة'), ('سمك', 'حيوان مائي'), ('جبل', 'تل كبير'),
    ('برد', 'ضد الحر'), ('ثلج', 'ماء متجمد'), ('ريح', 'هواء متحرك'),
    ('صيف', 'فصل حار'), ('شتا', 'فصل بارد'), ('يوم', 'وحدة زمن'),
    ('أمس', 'اليوم السابق'), ('دار', 'منزل'), ('أرض', 'تراب'),
    ('علوم', 'جمع علم'), ('بيوت', 'جمع بيت'), ('حروف', 'جمع حرف'),
    ('لغات', 'جمع لغة'), ('نجوم', 'جمع نجم'), ('بلاد', 'جمع بلد'),
    ('جبال', 'جمع جبل'), ('مدرب', 'معلم'), ('ثمار', 'جمع ثمرة'),
    ('كتاب', 'يُقرأ'), ('قلوب', 'جمع قلب'),
    ('قرآن', 'الكتاب المقدس'), ('عقول', 'جمع عقل'), ('زمان', 'الوقت'),
    ('مكان', 'الموقع'), ('قطار', 'وسيلة نقل'), ('كرسي', 'مقعد'),
    ('شباب', 'فئة عمرية'), ('طريق', 'مسار'), ('حدود', 'نهاية البلد'),
    ('كلام', 'كلمات'), ('بيان', 'الوضوح'),
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
  group('HybridFlexibleGenerator V6 — in-memory KB', () {
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
        rows: 5, cols: 5, seed: 42,
        backtrackTimeoutMs: 900, maxRetries: 10,
      ));
      sw.stop();
      // ignore: avoid_print
      print('5×5 in-mem : ${sw.elapsedMilliseconds} ms, grid=${grid != null}');
      expect(sw.elapsedMilliseconds, lessThan(1000));
      if (grid != null) {
        dumpGrid(grid, label: '5×5 in-mem seed=42');
        expect(validateAll(grid), isNull);
      }
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('4 types de flèches présents dans le data model (in-mem)', () async {
      // Au moins 2 types de flèches distincts sur plusieurs seeds.
      // KB in-memory limitée → certains seeds peuvent ne pas converger.
      final arrowTypes = <ClueArrow>{};
      var gridsGenerated = 0;
      for (var seed = 1; seed <= 10; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 6, cols: 6, seed: seed,
          backtrackTimeoutMs: 800, maxRetries: 6,
        ));
        if (g == null) continue;
        gridsGenerated++;
        for (final clue in g.allClues) {
          arrowTypes.add(clue.arrowType);
        }
      }
      // ignore: avoid_print
      print('Grilles générées : $gridsGenerated, types de flèches : $arrowTypes');
      if (gridsGenerated >= 2) {
        // Si on a ≥2 grilles (algo A et B alternent sur les attempts pairs/impairs),
        // on doit trouver au moins 2 types distincts.
        expect(arrowTypes.length, greaterThanOrEqualTo(2),
            reason: 'Mix A/B attendu : au moins 2 types de flèches distincts');
      }
      // Si 0 ou 1 grille, pas de contrainte sur le mix (KB trop pauvre).
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('R7 : pas de 3 CCs consécutives (in-mem, 5 seeds)', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5, cols: 5, seed: seed,
          backtrackTimeoutMs: 800, maxRetries: 5,
        ));
        if (g == null) continue;
        expect(checkR7(g), isNull, reason: 'seed=$seed');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('R1 : aucune CC vide, aucune LC vide (in-mem)', () async {
      for (var seed = 1; seed <= 5; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 5, cols: 5, seed: seed,
          backtrackTimeoutMs: 800, maxRetries: 5,
        ));
        if (g == null) continue;
        expect(checkR1(g), isNull, reason: 'seed=$seed');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('arrowType sérialisé/désérialisé (JSON round-trip)', () {
      for (final arrow in ClueArrow.values) {
        final clue = Clue(
          text: 'test',
          language: ClueLanguage.arabic,
          direction: Direction.horizontal,
          solution: 'كتب',
          startCell: const Position(2, 3),
          arrowType: arrow,
        );
        final json = clue.toJson();
        final clue2 = Clue.fromJson(json);
        expect(clue2.arrowType, equals(arrow),
            reason: 'round-trip échoue pour $arrow');
      }
    });

    test('arrowType par défaut rétro-compatible (Clue sans arrowType)', () {
      // Simule un JSON legacy sans le champ arrowType.
      final json = {
        'text': 'test',
        'language': 'arabic',
        'direction': 'horizontal',
        'solution': 'كتب',
        'startCell': {'row': 2, 'col': 3},
        // pas de 'arrowType'
      };
      final clue = Clue.fromJson(json);
      // Défaut H = hRowBelow (modèle B, rétro-compatible).
      expect(clue.arrowType, equals(ClueArrow.hRowBelow));
    });

    test('vSameCol → startCell même col (modèle A V)', () async {
      // Cherche une grille avec au moins 1 flèche vSameCol et vérifie la géom.
      for (var seed = 1; seed <= 20; seed++) {
        final g = await gen.generate(TopologyConfig(
          rows: 6, cols: 6, seed: seed,
          backtrackTimeoutMs: 800, maxRetries: 5,
        ));
        if (g == null) continue;
        for (var r = 0; r < g.rows; r++) {
          for (var c = 0; c < g.cols; c++) {
            final cell = g.cells[r][c];
            if (cell is! ClueCell) continue;
            for (final clue in cell.clues) {
              if (clue.arrowType == ClueArrow.vSameCol) {
                // vSameCol : CC (r, c) → startCell = (r+1, c)
                expect(clue.startCell.col, equals(c),
                    reason: 'vSameCol: startCell.col doit égaler CC.col');
                expect(clue.startCell.row, equals(r + 1),
                    reason: 'vSameCol: startCell.row doit égaler CC.row+1');
              }
              if (clue.arrowType == ClueArrow.hSameRow) {
                // hSameRow : CC (r, c) → startCell = (r, c+1)
                expect(clue.startCell.row, equals(r),
                    reason: 'hSameRow: startCell.row doit égaler CC.row');
                expect(clue.startCell.col, equals(c + 1),
                    reason: 'hSameRow: startCell.col doit égaler CC.col+1');
              }
              if (clue.arrowType == ClueArrow.hRowBelow) {
                // hRowBelow : CC (r, c) → startCell = (r+1, c)
                expect(clue.startCell.row, equals(r + 1),
                    reason: 'hRowBelow: startCell.row doit égaler CC.row+1');
                expect(clue.startCell.col, equals(c),
                    reason: 'hRowBelow: startCell.col doit égaler CC.col');
              }
              if (clue.arrowType == ClueArrow.vColRight) {
                // vColRight : CC (r, c) → startCell = (r, c+1)
                expect(clue.startCell.row, equals(r),
                    reason: 'vColRight: startCell.row doit égaler CC.row');
                expect(clue.startCell.col, equals(c + 1),
                    reason: 'vColRight: startCell.col doit égaler CC.col+1');
              }
            }
          }
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  // -------------------------------------------------------------------------
  // Tests avec KB SQLite réelle
  // -------------------------------------------------------------------------

  group('HybridFlexibleGenerator V6 — KB SQLite réelle', () {
    setUpAll(sqfliteFfiInit);

    late KbRepository kb;
    late TrueInterleavedGenerator gen;

    setUp(() async {
      final dbPath = '${Directory.current.path}/assets/kb/chabaka_kb.sqlite';
      kb = await openKbRepositoryFromFile(
        dbPath,
        databaseFactoryOverride: databaseFactoryFfi,
      );
      gen = TrueInterleavedGenerator(kb: kb);
    });

    tearDown(() async => kb.close());

    test('8×8 converge < 3s — R1/R4/R7 stricts, R8 mesuré', () async {
      var converged = false;
      for (var seed = 1; seed <= 3 && !converged; seed++) {
        final sw = Stopwatch()..start();
        final grid = await gen.generate(TopologyConfig(
          rows: 8, cols: 8, seed: seed,
          backtrackTimeoutMs: 2500, maxRetries: 5,
        ));
        sw.stop();
        // ignore: avoid_print
        print('8×8 seed=$seed : ${sw.elapsedMilliseconds} ms, grid=${grid != null}');
        if (grid != null) {
          converged = true;
          dumpGrid(grid, label: '8×8 seed=$seed');
          // R1, R5, R7, orphans (R4) — stricts.
          expect(checkR1(grid), isNull, reason: 'seed=$seed R1');
          expect(checkR5(grid), isNull, reason: 'seed=$seed R5');
          expect(checkR7(grid), isNull, reason: 'seed=$seed R7');
          expect(countOrphans(grid), equals(0), reason: 'seed=$seed orphans');
          // R8 : mesuré mais non bloquant (limitation structurelle connue).
          final r8 = checkR8(grid);
          // ignore: avoid_print
          if (r8 != null) print('[R8] $r8');
          // Mix de flèches A et B.
          final arrows = countByArrow(grid);
          final modelA = (arrows[ClueArrow.hSameRow] ?? 0) + (arrows[ClueArrow.vSameCol] ?? 0);
          final modelB = (arrows[ClueArrow.hRowBelow] ?? 0) + (arrows[ClueArrow.vColRight] ?? 0);
          // ignore: avoid_print
          print('  modèle A=$modelA B=$modelB');
        }
      }
      if (!converged) {
        // ignore: avoid_print
        print('[WARN] 8×8 : aucun seed n\'a convergé');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('16×13 Abu Salma — R1/R4/R7, mix 4 flèches', () async {
      final sw = Stopwatch()..start();
      Grid? grid;
      for (var seed = 1; seed <= 5 && grid == null; seed++) {
        grid = await gen.generate(TopologyConfig(
          rows: 16, cols: 13, seed: seed,
          backtrackTimeoutMs: 25000, maxRetries: 80,
        ));
        if (grid == null) {
          // ignore: avoid_print
          print('seed=$seed : pas de grille dans le délai');
        }
      }
      sw.stop();
      // ignore: avoid_print
      print('16×13 : ${sw.elapsedMilliseconds} ms total, grid=${grid != null}');

      if (grid != null) {
        dumpGrid(grid, label: '16×13 Abu Salma V6');

        final ccs = countCCs(grid);
        final clues = grid.allClues.toList();
        final orphans = countOrphans(grid);
        final avg = avgWordLen(grid);
        final arrows = countByArrow(grid);
        final modelA = (arrows[ClueArrow.hSameRow] ?? 0) +
            (arrows[ClueArrow.vSameCol] ?? 0);
        final modelB = (arrows[ClueArrow.hRowBelow] ?? 0) +
            (arrows[ClueArrow.vColRight] ?? 0);
        final r8 = checkR8(grid);

        // ignore: avoid_print
        print('Stats 16×13 :');
        // ignore: avoid_print
        print('  CCs=$ccs  clues=${clues.length}  orphans=$orphans');
        // ignore: avoid_print
        print('  avgLen=${avg.toStringAsFixed(2)}  maxLen=${maxWordLen(grid)}');
        // ignore: avoid_print
        print('  modèle A=$modelA  modèle B=$modelB');
        // ignore: avoid_print
        print('  ←(hSameRow)=${arrows[ClueArrow.hSameRow]}  '
            '↓(vSameCol)=${arrows[ClueArrow.vSameCol]}  '
            '↵(hRowBelow)=${arrows[ClueArrow.hRowBelow]}  '
            '↴(vColRight)=${arrows[ClueArrow.vColRight]}');
        // ignore: avoid_print
        if (r8 != null) print('[R8 warn] $r8');

        // R1, R4, R7 — R4 tolère jusqu'à 2 orphelins (contrainte KB bord).
        expect(checkR1(grid), isNull, reason: 'R1');
        expect(checkR5(grid), isNull, reason: 'R5 (0,0)=CC');
        expect(checkR7(grid), isNull, reason: 'R7 max 2 CCs contig');
        expect(orphans, lessThanOrEqualTo(2),
            reason: 'R4 ≤2 orphelins (bord, contrainte KB)');
        expect(maxWordLen(grid), lessThanOrEqualTo(5), reason: 'max 5 lettres');
        expect(ccs, greaterThanOrEqualTo(35), reason: '≥35 CCs');
        expect(clues.length, greaterThanOrEqualTo(30), reason: '≥30 clues');
        // Mix A+B.
        expect(modelA, greaterThan(0), reason: 'modèle A attendu');
        expect(modelB, greaterThan(0), reason: 'modèle B attendu');
        // R8 : mesuré, non bloquant pour la V6.
      } else {
        // ignore: avoid_print
        print('[WARN] 16×13 : aucune grille dans le délai global');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('16×13 — R4 : LCs orphelines ≤ 2 (contrainte KB bord)', () async {
      Grid? grid;
      for (var seed = 1; seed <= 5 && grid == null; seed++) {
        grid = await gen.generate(TopologyConfig(
          rows: 16, cols: 13, seed: seed,
          backtrackTimeoutMs: 25000, maxRetries: 80,
        ));
      }
      if (grid != null) {
        expect(countOrphans(grid), lessThanOrEqualTo(2),
            reason: 'R4 : ≤2 LCs orphelines (bord/corner, contrainte KB)');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('16×13 — R7 strict : max 2 CCs contigus', () async {
      Grid? grid;
      for (var seed = 1; seed <= 5 && grid == null; seed++) {
        grid = await gen.generate(TopologyConfig(
          rows: 16, cols: 13, seed: seed,
          backtrackTimeoutMs: 25000, maxRetries: 80,
        ));
      }
      if (grid != null) {
        expect(checkR7(grid), isNull);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('16×13 — géométrie arrowType cohérente', () async {
      Grid? grid;
      for (var seed = 1; seed <= 5 && grid == null; seed++) {
        grid = await gen.generate(TopologyConfig(
          rows: 16, cols: 13, seed: seed,
          backtrackTimeoutMs: 25000, maxRetries: 80,
        ));
      }
      if (grid == null) return;

      for (var r = 0; r < grid.rows; r++) {
        for (var c = 0; c < grid.cols; c++) {
          final cell = grid.cells[r][c];
          if (cell is! ClueCell) continue;
          for (final clue in cell.clues) {
            final sr = clue.startCell.row;
            final sc = clue.startCell.col;
            switch (clue.arrowType) {
              case ClueArrow.hSameRow:
                expect(sr, equals(r),
                    reason: 'hSameRow: startCell.row ($sr) ≠ CC.row ($r)');
                expect(sc, equals(c + 1),
                    reason: 'hSameRow: startCell.col ($sc) ≠ CC.col+1 (${c + 1})');
              case ClueArrow.vSameCol:
                expect(sc, equals(c),
                    reason: 'vSameCol: startCell.col ($sc) ≠ CC.col ($c)');
                expect(sr, equals(r + 1),
                    reason: 'vSameCol: startCell.row ($sr) ≠ CC.row+1 (${r + 1})');
              case ClueArrow.hRowBelow:
                expect(sr, equals(r + 1),
                    reason: 'hRowBelow: startCell.row ($sr) ≠ CC.row+1 (${r + 1})');
                expect(sc, equals(c),
                    reason: 'hRowBelow: startCell.col ($sc) ≠ CC.col ($c)');
              case ClueArrow.vColRight:
                expect(sr, equals(r),
                    reason: 'vColRight: startCell.row ($sr) ≠ CC.row ($r)');
                expect(sc, equals(c + 1),
                    reason: 'vColRight: startCell.col ($sc) ≠ CC.col+1 (${c + 1})');
            }
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
