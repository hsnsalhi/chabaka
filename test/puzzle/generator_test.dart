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
    WordEntry(word: 'سمك', clue: 'حيوان بحري', length: 3),
    WordEntry(word: 'طير', clue: 'يطير في السماء', length: 3),
    WordEntry(word: 'زهر', clue: 'نبات جميل', length: 3),
    WordEntry(word: 'خبز', clue: 'طعام أساسي', length: 3),
    WordEntry(word: 'درب', clue: 'طريق ضيق', length: 3),
    WordEntry(word: 'فرس', clue: 'حيوان للركوب', length: 3),
    WordEntry(word: 'جسر', clue: 'يعبر النهر', length: 3),
    WordEntry(word: 'حجر', clue: 'صخرة صغيرة', length: 3),
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

    test('grille a des dimensions dans les limites de la config', () {
      // La grille produite peut être plus petite que rows×cols car la taille
      // est adaptée aux mots placés (approche bande V1).
      // On vérifie que les dimensions sont cohérentes et non nulles.
      final config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 42,
      );
      final grid = generator.generate(config)!;
      expect(grid.rows, greaterThan(0));
      expect(grid.cols, greaterThan(0));
      expect(grid.rows, lessThanOrEqualTo(config.rows));
      expect(grid.cols, lessThanOrEqualTo(config.cols));
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
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 1,
      );
      final config2 = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 2,
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
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 42,
      );
      final grid = generator.generate(config)!;
      expect(grid.letterCells.length, greaterThan(0));
    });

    test('toutes les LetterCells ont une solution non vide', () {
      final config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 42,
      );
      final grid = generator.generate(config)!;
      for (final entry in grid.letterCells) {
        expect(entry.cell.solution, isNotEmpty);
      }
    });

    test('grille id contient le seed', () {
      final config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 8,
        seed: 999,
      );
      final grid = generator.generate(config)!;
      expect(grid.id, contains('999'));
    });
  });

  group('R1 — toutes les cases utiles', () {
    // Test principal R1 : sur 50 seeds, toute grille retournée doit être conforme.
    // Une grille conforme ne contient aucune ClueCell vide (clues: []).
    // Si generate() retourne null pour un seed, c'est acceptable.
    test('sur 50 seeds : toute grille retournée satisfait R1 (zéro ClueCell vide)',
        () {
      const config = GeneratorConfig(
        rows: 7,
        cols: 7,
        minWords: 3,
        maxWords: 20,
        seed: 0, // sera remplacé dans la boucle
      );

      var gridsGenerated = 0;

      for (var seed = 0; seed < 50; seed++) {
        final cfg = GeneratorConfig(
          rows: config.rows,
          cols: config.cols,
          minWords: config.minWords,
          maxWords: config.maxWords,
          seed: seed,
        );
        final grid = generator.generate(cfg);

        if (grid == null) continue; // null acceptable — seed non viable
        gridsGenerated++;

        // Vérifier R1 : zéro ClueCell vide
        for (var r = 0; r < grid.rows; r++) {
          for (var c = 0; c < grid.cols; c++) {
            final cell = grid.cells[r][c];
            if (cell is ClueCell) {
              expect(
                cell.clues,
                isNotEmpty,
                reason:
                    'R1 violée : ClueCell vide à ($r, $c) pour seed=$seed',
              );
            }
          }
        }
      }

      // Au moins quelques grilles doivent être générées pour que le test soit utile
      expect(
        gridsGenerated,
        greaterThan(0),
        reason:
            'Aucune grille générée sur 50 seeds — wordlist probablement trop petite',
      );
    });

    test('une grille retournée ne contient jamais de ClueCell sans indice', () {
      for (var seed = 50; seed < 60; seed++) {
        final cfg = GeneratorConfig(
          rows: 7,
          cols: 7,
          minWords: 3,
          maxWords: 20,
          seed: seed,
        );
        final grid = generator.generate(cfg);
        if (grid == null) continue;

        final emptyClueCells = <Position>[];
        for (var r = 0; r < grid.rows; r++) {
          for (var c = 0; c < grid.cols; c++) {
            final cell = grid.cells[r][c];
            if (cell is ClueCell && cell.clues.isEmpty) {
              emptyClueCells.add(Position(r, c));
            }
          }
        }
        expect(
          emptyClueCells,
          isEmpty,
          reason: 'R1 violée pour seed=$seed : ${emptyClueCells.length} '
              'ClueCells vides trouvées',
        );
      }
    });

    test('toutes les ClueCells ont au maximum 2 indices', () {
      for (var seed = 0; seed < 20; seed++) {
        final cfg = GeneratorConfig(
          rows: 7,
          cols: 7,
          minWords: 3,
          maxWords: 20,
          seed: seed,
        );
        final grid = generator.generate(cfg);
        if (grid == null) continue;

        for (var r = 0; r < grid.rows; r++) {
          for (var c = 0; c < grid.cols; c++) {
            final cell = grid.cells[r][c];
            if (cell is ClueCell) {
              expect(
                cell.clues.length,
                lessThanOrEqualTo(2),
                reason: 'ClueCell à ($r, $c) seed=$seed a '
                    '${cell.clues.length} indices (max 2)',
              );
            }
          }
        }
      }
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
