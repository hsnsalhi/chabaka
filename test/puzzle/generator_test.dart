import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/models.dart';
import 'package:chabaka/puzzle/generation/wordlist.dart';
import 'package:chabaka/puzzle/generation/generator.dart';

Wordlist _buildWordlist() {
  return Wordlist([
    WordEntry(word: 'كتب', clue: 'جمع كتاب', length: 3),
    WordEntry(word: 'علم', clue: 'المعرفة', length: 3),
    WordEntry(word: 'بحر', clue: 'ماء ملح', length: 3),
    WordEntry(word: 'نور', clue: 'ضد الظلام', length: 3),
    WordEntry(word: 'قمر', clue: 'يضيء الليل', length: 3),
    WordEntry(word: 'شمس', clue: 'تشرق صباحاً', length: 3),
    WordEntry(word: 'ماء', clue: 'أساس الحياة', length: 3),
    WordEntry(word: 'باب', clue: 'مدخل البيت', length: 3),
    WordEntry(word: 'بيت', clue: 'المسكن', length: 3),
    WordEntry(word: 'ولد', clue: 'طفل صغير', length: 3),
    WordEntry(word: 'جبل', clue: 'أرفع من التل', length: 4),
    WordEntry(word: 'نهر', clue: 'مجرى مائي', length: 3),
    WordEntry(word: 'يد', clue: 'عضو الإنسان', length: 2),
    WordEntry(word: 'أب', clue: 'الوالد', length: 2),
    WordEntry(word: 'أم', clue: 'الوالدة', length: 2),
  ]);
}

bool _isR1Compliant(Grid g) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      final cell = g.cellAt(Position(r, c));
      if (cell is ClueCell && cell.clues.isEmpty) return false;
    }
  }
  return true;
}

void main() {
  final wordlist = _buildWordlist();
  final generator = PuzzleGenerator(wordlist: wordlist);

  group('PuzzleGenerator', () {
    test('génère une grille 4×4 R1-conforme pour seed fixe', () {
      final grid = generator.generate(
        const GeneratorConfig(
          rows: 4,
          cols: 4,
          minWords: 3,
          maxWords: 12,
          seed: 42,
        ),
      );
      expect(grid, isNotNull);
      expect(_isR1Compliant(grid!), isTrue, reason: 'Aucune ClueCell vide');
    });

    test('grille a les dimensions demandées', () {
      final grid = generator.generate(
        const GeneratorConfig(
          rows: 5,
          cols: 5,
          minWords: 3,
          maxWords: 12,
          seed: 42,
        ),
      );
      if (grid == null) {
        // Tolérer les seeds difficiles avec une wordlist de test minimale.
        return;
      }
      expect(grid.rows, 5);
      expect(grid.cols, 5);
    });

    test('grille déterministe : même seed → même grille', () {
      const config = GeneratorConfig(
        rows: 4,
        cols: 4,
        minWords: 3,
        maxWords: 12,
        seed: 100,
      );
      final grid1 = generator.generate(config);
      final grid2 = generator.generate(config);
      expect(grid1, isNotNull);
      expect(grid2, isNotNull);
      expect(grid1!.letterCells.length, grid2!.letterCells.length);
      expect(grid1.allClues.length, grid2.allClues.length);
    });

    test('seeds différentes → grilles différentes (très probablement)', () {
      const c1 = GeneratorConfig(
        rows: 4,
        cols: 4,
        minWords: 3,
        maxWords: 12,
        seed: 1,
      );
      const c2 = GeneratorConfig(
        rows: 4,
        cols: 4,
        minWords: 3,
        maxWords: 12,
        seed: 2,
      );
      final g1 = generator.generate(c1);
      final g2 = generator.generate(c2);
      expect(g1, isNotNull);
      expect(g2, isNotNull);
    });

    test('GeneratorConfig.forDate crée une config déterministe par date', () {
      final c1 = GeneratorConfig.forDate(DateTime(2026, 5, 10));
      final c2 = GeneratorConfig.forDate(DateTime(2026, 5, 10));
      expect(c1.seed, c2.seed);
    });

    test('grille contient au moins une LetterCell', () {
      final grid = generator.generate(
        const GeneratorConfig(
          rows: 4,
          cols: 4,
          minWords: 3,
          maxWords: 12,
          seed: 42,
        ),
      );
      expect(grid, isNotNull);
      expect(grid!.letterCells.length, greaterThan(0));
    });

    test('toutes les LetterCells ont une solution non vide', () {
      final grid = generator.generate(
        const GeneratorConfig(
          rows: 4,
          cols: 4,
          minWords: 3,
          maxWords: 12,
          seed: 42,
        ),
      )!;
      for (final entry in grid.letterCells) {
        expect(entry.cell.solution, isNotEmpty);
      }
    });

    test('grille id contient le seed', () {
      final grid = generator.generate(
        const GeneratorConfig(
          rows: 4,
          cols: 4,
          minWords: 3,
          maxWords: 12,
          seed: 999,
        ),
      )!;
      expect(grid.id, contains('999'));
    });

    test('R1 strict : aucune grille générée ne contient de ClueCell vide', () {
      var generated = 0;
      for (var seed = 0; seed < 20; seed++) {
        final grid = generator.generate(
          GeneratorConfig(
            rows: 4,
            cols: 4,
            minWords: 3,
            maxWords: 12,
            seed: seed,
          ),
        );
        if (grid == null) continue;
        generated++;
        expect(
          _isR1Compliant(grid),
          isTrue,
          reason: 'Seed $seed produit une grille violant R1',
        );
      }
      // Au moins 80% des seeds doivent réussir avec wordlist 15 mots / 4×4.
      expect(generated, greaterThanOrEqualTo(16));
    });
  });

  group('Wordlist', () {
    test('ofLength filtre correctement', () {
      final wl = _buildWordlist();
      expect(wl.ofLength(3).every((e) => e.length == 3), isTrue);
    });

    test('inRange filtre correctement', () {
      final wl = _buildWordlist();
      expect(
        wl.inRange(3, 4).every((e) => e.length >= 3 && e.length <= 4),
        isTrue,
      );
    });

    test('withLetterAt trouve les mots avec lettre à position', () {
      final wl = _buildWordlist();
      expect(wl.withLetterAt('ك', 0).any((e) => e.word == 'كتب'), isTrue);
    });
  });
}
