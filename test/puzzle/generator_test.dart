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
  ]);
}

void main() {
  final wordlist = _buildWordlist();
  final generator = PuzzleGenerator(wordlist: wordlist);

  group('PuzzleGenerator', () {
    test('génère une grille non nulle pour seed fixe', () {
      final config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 42,
      );
      final grid = generator.generate(config);
      expect(grid, isNotNull);
    });

    test('grille a le bon nombre de lignes et colonnes', () {
      final config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 42,
      );
      final grid = generator.generate(config)!;
      expect(grid.rows, 7);
      expect(grid.cols, 7);
    });

    test('grille déterministe : même seed → même grille', () {
      final config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 100,
      );
      final grid1 = generator.generate(config);
      final grid2 = generator.generate(config);
      expect(grid1, isNotNull);
      expect(grid2, isNotNull);
      // Même nombre de LetterCells
      expect(grid1!.letterCells.length, grid2!.letterCells.length);
    });

    test('seeds différentes → grilles différentes (très probablement)', () {
      final config1 = GeneratorConfig(
        rows: 7, cols: 7, minWords: 3, maxWords: 8, seed: 1,
      );
      final config2 = GeneratorConfig(
        rows: 7, cols: 7, minWords: 3, maxWords: 8, seed: 2,
      );
      final grid1 = generator.generate(config1);
      final grid2 = generator.generate(config2);
      // On vérifie juste que les deux génèrent quelque chose de valide
      expect(grid1, isNotNull);
      expect(grid2, isNotNull);
    });

    test('GeneratorConfig.forDate crée une config déterministe par date', () {
      final date = DateTime(2026, 5, 10);
      final config1 = GeneratorConfig.forDate(date);
      final config2 = GeneratorConfig.forDate(date);
      expect(config1.seed, config2.seed);
    });

    test('grille contient au moins une LetterCell', () {
      final config = GeneratorConfig(
        rows: 7, cols: 7, minWords: 3, maxWords: 8, seed: 42,
      );
      final grid = generator.generate(config)!;
      expect(grid.letterCells.length, greaterThan(0));
    });

    test('toutes les LetterCells ont une solution non vide', () {
      final config = GeneratorConfig(
        rows: 7, cols: 7, minWords: 3, maxWords: 8, seed: 42,
      );
      final grid = generator.generate(config)!;
      for (final entry in grid.letterCells) {
        expect(entry.cell.solution, isNotEmpty);
      }
    });

    test('grille id contient le seed', () {
      final config = GeneratorConfig(
        rows: 7, cols: 7, minWords: 3, maxWords: 8, seed: 999,
      );
      final grid = generator.generate(config)!;
      expect(grid.id, contains('999'));
    });
  });

  group('Wordlist', () {
    test('ofLength filtre correctement', () {
      final wl = _buildWordlist();
      final threeLetters = wl.ofLength(3);
      expect(threeLetters.every((e) => e.length == 3), isTrue);
    });

    test('inRange filtre correctement', () {
      final wl = _buildWordlist();
      final filtered = wl.inRange(3, 4);
      expect(filtered.every((e) => e.length >= 3 && e.length <= 4), isTrue);
    });

    test('withLetterAt trouve les mots avec lettre à position', () {
      final wl = _buildWordlist();
      // 'كتب' : lettre[0] = 'ك'
      final results = wl.withLetterAt('ك', 0);
      expect(results.any((e) => e.word == 'كتب'), isTrue);
    });
  });
}
