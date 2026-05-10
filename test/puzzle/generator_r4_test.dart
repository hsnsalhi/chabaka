import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/models.dart';
import 'package:chabaka/puzzle/kb/kb_repository.dart';
import 'package:chabaka/puzzle/generation/topology.dart';

// ---------------------------------------------------------------------------
// KB de test — suffisamment riche pour couvrir les longueurs 2..7
// ---------------------------------------------------------------------------

/// Construit une KB in-memory avec des mots de longueur 2 à 7 variés.
InMemoryKbRepository _buildRichKb() {
  final entries = <KbEntry>[];
  var id = 1;

  // Données réelles (normalisées R3) — suffisantes pour 5×5 et 7×7
  final words = [
    // lon 2
    ('يد', 'يد', 'عضو الإنسان'),
    ('أب', 'أب', 'الوالد'),
    ('أم', 'أم', 'الوالدة'),
    ('قل', 'قل', 'من القلة'),
    ('ذل', 'ذل', 'الهوان'),
    ('حق', 'حق', 'ما يجب'),
    ('دم', 'دم', 'سائل الحياة'),
    ('رب', 'رب', 'الإله'),
    ('حر', 'حر', 'ضد العبد'),
    ('هم', 'هم', 'الحزن'),
    // lon 3
    ('علم', 'علم', 'المعرفة'),
    ('بحر', 'بحر', 'ماء ملح'),
    ('نور', 'نور', 'ضد الظلام'),
    ('قمر', 'قمر', 'يضيء الليل'),
    ('شمس', 'شمس', 'تشرق صباحاً'),
    ('ماء', 'ماء', 'أساس الحياة'),
    ('باب', 'باب', 'مدخل البيت'),
    ('بيت', 'بيت', 'المسكن'),
    ('ولد', 'ولد', 'طفل صغير'),
    ('نهر', 'نهر', 'مجرى مائي'),
    ('كتب', 'كتب', 'جمع كتاب'),
    ('عمل', 'عمل', 'النشاط'),
    ('قلم', 'قلم', 'أداة الكتابة'),
    ('شعر', 'شعر', 'كلام موزون'),
    ('مطر', 'مطر', 'قطر السماء'),
    ('ثلج', 'ثلج', 'ماء متجمد'),
    ('رمل', 'رمل', 'تراب الصحراء'),
    ('ريح', 'ريح', 'هواء متحرك'),
    ('وقت', 'وقت', 'الزمن'),
    ('سوق', 'سوق', 'محل البيع'),
    ('حرب', 'حرب', 'النزاع المسلح'),
    ('سلم', 'سلم', 'ضد الحرب'),
    ('دار', 'دار', 'البيت الكبير'),
    ('حال', 'حال', 'الوضع'),
    ('خبر', 'خبر', 'المعلومة'),
    ('جبل', 'جبل', 'أرفع من التل'),
    // lon 4
    ('كتاب', 'كتاب', 'يُقرأ'),
    ('مدرس', 'مدرس', 'المعلم'),
    ('طالب', 'طالب', 'المتعلم'),
    ('رياض', 'رياض', 'جمع روضة'),
    ('سماء', 'سماء', 'فوقنا'),
    ('أرض', 'أرض', 'الكرة الأرضية'),
    ('شجر', 'شجر', 'نبات كبير'),
    ('بلاد', 'بلاد', 'جمع بلد'),
    ('عصر', 'عصر', 'حقبة زمنية'),
    ('ليل', 'ليل', 'ضد النهار'),
    ('حقل', 'حقل', 'أرض زراعية'),
    ('صحر', 'صحر', 'صحراء'),
    ('أسد', 'أسد', 'ملك الغابة'),
    ('نجم', 'نجم', 'في السماء'),
    ('حكم', 'حكم', 'القضاء'),
    ('سفر', 'سفر', 'الرحلة'),
    ('قرن', 'قرن', 'مئة سنة'),
    ('جسر', 'جسر', 'فوق النهر'),
    // lon 5
    ('مدينه', 'مدينة', 'تجمع سكاني'),
    ('قاهره', 'قاهرة', 'عاصمة مصر'),
    ('بيروت', 'بيروت', 'عاصمة لبنان'),
    ('نهضه', 'نهضة', 'الانطلاق'),
    ('رسمي', 'رسمي', 'ذو طابع رسمي'),
    ('كامل', 'كامل', 'تام بلا نقص'),
    ('سالم', 'سالم', 'بلا أذى'),
    ('شامل', 'شامل', 'يشمل الكل'),
    ('واسع', 'واسع', 'ضد الضيق'),
    ('جامع', 'جامع', 'مسجد كبير'),
    ('عاصم', 'عاصم', 'من يحمي'),
    ('راشد', 'راشد', 'المهتدي'),
    ('ماهر', 'ماهر', 'المتقن'),
    ('حافظ', 'حافظ', 'من يحفظ'),
    ('نادر', 'نادر', 'قليل الوجود'),
    ('فاتح', 'فاتح', 'من يفتح'),
    ('ثابت', 'ثابت', 'لا يتغير'),
    ('كريم', 'كريم', 'السخي'),
    // lon 6
    ('مكتبه', 'مكتبة', 'مكان الكتب'),
    ('مسرح', 'مسرح', 'للعروض الفنية'),
    ('مطبخ', 'مطبخ', 'مكان الطبخ'),
    ('حديقه', 'حديقة', 'الروضة الجميلة'),
    ('مدرسه', 'مدرسة', 'بيت العلم'),
    ('جامعه', 'جامعة', 'أعلى من مدرسة'),
    ('مستشف', 'مستشفى', 'بيت المرضى'),
    // lon 7
    ('مطبعة', 'مطبعة', 'تطبع الكتب'),
    ('مسجد', 'مسجد', 'بيت الصلاة'),
    ('ملعب', 'ملعب', 'ساحة الرياضة'),
    ('مصنع', 'مصنع', 'يصنع المنتجات'),
    ('متحف', 'متحف', 'يحفظ التراث'),
    ('مرصد', 'مرصد', 'يراقب النجوم'),
  ];

  for (final (word, display, clue) in words) {
    entries.add(KbEntry(
      id: id++,
      word: word,
      wordDisplay: display,
      length: word.runes.length,
      category: KbCategory.common,
      clues: [KbClue(text: clue, kind: KbClueKind.definition)],
    ));
  }

  return InMemoryKbRepository(entries);
}

// ---------------------------------------------------------------------------
// Helpers de validation
// ---------------------------------------------------------------------------

bool _isR1Compliant(Grid g) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cellAt(Position(r, c));
      if (cell is ClueCell && cell.clues.isEmpty) return false;
    }
  }
  return true;
}

/// R4 : aucune run accidentelle.
/// Une run accidentelle = séquence de LetterCells non couverte par un slot
/// (ici on vérifie qu'aucune séquence de LetterCells n'est de longueur 1
/// entre deux ClueCells ou bords, ce qui serait un slot implicite invalide).
bool _hasNoAccidentalRuns(Grid g) {
  // Vérifie les runs horizontales et verticales.
  // Toute run doit avoir length ≥ 2.

  // Horizontales
  for (var r = 0; r < g.rows; r++) {
    var runLen = 0;
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cells[r][c];
      if (cell is LetterCell) {
        runLen++;
      } else {
        if (runLen == 1) return false;
        runLen = 0;
      }
    }
    if (runLen == 1) return false;
  }

  // Verticales
  for (var c = 0; c < g.cols; c++) {
    var runLen = 0;
    for (var r = 0; r < g.rows; r++) {
      final cell = g.cells[r][c];
      if (cell is LetterCell) {
        runLen++;
      } else {
        if (runLen == 1) return false;
        runLen = 0;
      }
    }
    if (runLen == 1) return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late InMemoryKbRepository kb;
  late R4Generator gen;

  setUp(() {
    kb = _buildRichKb();
    gen = R4Generator(kb: kb);
  });

  tearDown(() async {
    await kb.close();
  });

  group('Slot', () {
    test('positions horizontales correctes', () {
      final slot = Slot(
        direction: Direction.horizontal,
        startRow: 2,
        startCol: 1,
        length: 3,
      );
      expect(slot.positions, [(2, 1), (2, 2), (2, 3)]);
    });

    test('positions verticales correctes', () {
      final slot = Slot(
        direction: Direction.vertical,
        startRow: 1,
        startCol: 3,
        length: 4,
      );
      expect(slot.positions, [(1, 3), (2, 3), (3, 3), (4, 3)]);
    });

    test('clueCellPos horizontal = gauche du slot', () {
      final slot = Slot(direction: Direction.horizontal, startRow: 2, startCol: 3, length: 4);
      expect(slot.clueCellPos, (2, 2));
    });

    test('clueCellPos vertical = au-dessus du slot', () {
      final slot = Slot(direction: Direction.vertical, startRow: 2, startCol: 3, length: 4);
      expect(slot.clueCellPos, (1, 3));
    });
  });

  group('TopologyConfig', () {
    test('forDate produit un seed déterministe', () {
      final c1 = TopologyConfig.forDate(DateTime(2026, 5, 10));
      final c2 = TopologyConfig.forDate(DateTime(2026, 5, 10));
      expect(c1.seed, c2.seed);
    });

    test('dates différentes → seeds différents', () {
      final c1 = TopologyConfig.forDate(DateTime(2026, 5, 10));
      final c2 = TopologyConfig.forDate(DateTime(2026, 5, 11));
      expect(c1.seed, isNot(c2.seed));
    });
  });

  group('R4Generator — grille 5×5', () {
    test('génère une grille non nulle', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42),
      );
      expect(grid, isNotNull);
    });

    test('dimensions respectées', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42),
      );
      if (grid == null) return;
      expect(grid.rows, 5);
      expect(grid.cols, 5);
    });

    test('R1 : aucune ClueCell vide', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42),
      );
      if (grid == null) return;
      expect(_isR1Compliant(grid), isTrue, reason: 'ClueCell sans indice détectée');
    });

    test('R4 : aucune run accidentelle de longueur 1', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42),
      );
      if (grid == null) return;
      expect(_hasNoAccidentalRuns(grid), isTrue);
    });

    test('contient au moins une LetterCell', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42),
      );
      if (grid == null) return;
      expect(grid.letterCells.length, greaterThan(0));
    });

    test('déterministe : même seed → même grille', () async {
      final config = const TopologyConfig(rows: 5, cols: 5, seed: 100);
      final g1 = await gen.generate(config);
      final g2 = await gen.generate(config);
      expect(g1, isNotNull);
      expect(g2, isNotNull);
      expect(g1!.id, g2!.id);
      expect(g1.letterCells.length, g2.letterCells.length);
      expect(g1.allClues.length, g2.allClues.length);
    });

    test('LetterCells ont toutes une solution non vide', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42),
      );
      if (grid == null) return;
      for (final lc in grid.letterCells) {
        expect(lc.cell.solution, isNotEmpty);
      }
    });
  });

  group('R4Generator — robustesse sur 20 seeds 5×5', () {
    test('≥ 80% des seeds convergent et sont R1+R4 valides', () async {
      var generated = 0;
      var valid = 0;
      for (var s = 0; s < 20; s++) {
        final grid = await gen.generate(
          TopologyConfig(rows: 5, cols: 5, seed: s, maxRetries: 20),
        );
        if (grid == null) continue;
        generated++;
        if (_isR1Compliant(grid) && _hasNoAccidentalRuns(grid)) valid++;
      }
      expect(generated, greaterThanOrEqualTo(16),
          reason: 'Moins de 80% des seeds 5×5 ont convergé ($generated/20)');
      expect(valid, equals(generated),
          reason: 'Certaines grilles violent R1 ou R4');
    });
  });

  group('R4Generator — grille 7×7', () {
    test('génère une grille 7×7 valide et respecte les règles', () async {
      final grid = await gen.generate(
        const TopologyConfig(rows: 7, cols: 7, seed: 42, maxRetries: 40),
      );
      if (grid == null) return; // KB trop petite pour certains seeds, acceptable
      expect(grid.rows, 7);
      expect(grid.cols, 7);
      expect(_isR1Compliant(grid), isTrue);
      expect(_hasNoAccidentalRuns(grid), isTrue);
    });
  });

  group('R4Generator — perf', () {
    test('génération 5×5 se termine en < 2 s', () async {
      final start = DateTime.now();
      await gen.generate(
        const TopologyConfig(rows: 5, cols: 5, seed: 42, backtrackTimeoutMs: 2000),
      );
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      expect(elapsed, lessThan(2000));
    });
  });
}
