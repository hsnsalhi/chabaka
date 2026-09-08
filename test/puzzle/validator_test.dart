import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/models.dart';
import 'package:chabaka/puzzle/validator.dart';

/// Grille 2×3 : une clue horizontale "كتب" (ligne 0 : cols 1-2 + ligne 1 col 0)
///
///  [ClueCell("كتب →")]  [LetterCell('ك')]  [LetterCell('ت')]
///  [LetterCell('ب')]    [LetterCell('ر')]  [LetterCell('س')]
Grid _buildGrid({Map<Position, String> userInputs = const {}}) {
  final cells = <List<Cell>>[
    [
      ClueCell(
        clues: [
          Clue(
            text: 'كتب',
            language: ClueLanguage.arabic,
            direction: Direction.horizontal,
            solution: 'كتب',
            startCell: Position(0, 1),
          ),
        ],
      ),
      LetterCell(solution: 'ك'),
      LetterCell(solution: 'ت'),
    ],
    [
      LetterCell(solution: 'ب'),
      LetterCell(solution: 'ر'),
      LetterCell(solution: 'س'),
    ],
  ];

  // Appliquer les userInputs
  for (final entry in userInputs.entries) {
    final cell = cells[entry.key.row][entry.key.col];
    if (cell is LetterCell) cell.userInput = entry.value;
  }

  return Grid(
    rows: 2,
    cols: 3,
    id: 'val-test',
    variant: GridVariant.standard,
    cells: cells,
  );
}

void main() {
  const validator = GridValidator();

  group('GridValidator — word validation', () {
    test('all empty → WordStatus.empty', () {
      final grid = _buildGrid();
      final clue = grid.allClues.first;
      final result = validator.validateWord(grid, clue);
      expect(result.status, WordStatus.empty);
    });

    test('partial fill → WordStatus.partial', () {
      final grid = _buildGrid(userInputs: {Position(0, 1): 'ك'});
      final clue = grid.allClues.first;
      final result = validator.validateWord(grid, clue);
      expect(result.status, WordStatus.partial);
    });

    test('correct fill → WordStatus.correct', () {
      // Note : le mot "كتب" (3 lettres) ne tient pas dans la grille de
      // _buildGrid, on construit donc une grille dédiée avec un mot de
      // 2 lettres pour tester la complétion propre.
      // Grille avec mot "كت" (2 lettres) pour tester la complétion propre
      final clue2 = Clue(
        text: 'test',
        language: ClueLanguage.arabic,
        direction: Direction.horizontal,
        solution: 'كت',
        startCell: Position(0, 1),
      );
      final grid2 = Grid(
        rows: 2,
        cols: 3,
        id: 'v2',
        variant: GridVariant.standard,
        cells: [
          [
            ClueCell(clues: [clue2]),
            LetterCell(solution: 'ك')..userInput = 'ك',
            LetterCell(solution: 'ت')..userInput = 'ت',
          ],
          [
            LetterCell(solution: 'ب'),
            LetterCell(solution: 'ر'),
            LetterCell(solution: 'س'),
          ],
        ],
      );
      final result = validator.validateWord(grid2, clue2);
      expect(result.status, WordStatus.correct);
    });

    test('wrong letter → WordStatus.incorrect', () {
      final clue = Clue(
        text: 'test',
        language: ClueLanguage.arabic,
        direction: Direction.horizontal,
        solution: 'كت',
        startCell: Position(0, 1),
      );
      final grid = Grid(
        rows: 1,
        cols: 3,
        id: 'v3',
        variant: GridVariant.standard,
        cells: [
          [
            ClueCell(clues: [clue]),
            LetterCell(solution: 'ك')..userInput = 'ب', // wrong
            LetterCell(solution: 'ت')..userInput = 'ت',
          ],
        ],
      );
      final result = validator.validateWord(grid, clue);
      expect(result.status, WordStatus.incorrect);
    });

    test('alef variant accepted (أ matches ا)', () {
      final clue = Clue(
        text: 'test',
        language: ClueLanguage.arabic,
        direction: Direction.horizontal,
        solution: 'الم',
        startCell: Position(0, 0),
      );
      final grid = Grid(
        rows: 1,
        cols: 3,
        id: 'v4',
        variant: GridVariant.standard,
        cells: [
          [
            LetterCell(solution: 'ا')..userInput = 'أ', // variant
            LetterCell(solution: 'ل')..userInput = 'ل',
            LetterCell(solution: 'م')..userInput = 'م',
          ],
        ],
      );
      // Pas de ClueCell ici — validation via validateWord directement
      final result = validator.validateWord(grid, clue);
      expect(result.status, WordStatus.correct);
    });
  });

  group('GridValidator — grid status', () {
    test('incomplete grid → GridStatus.incomplete', () {
      final grid = _buildGrid();
      final result = validator.validateGrid(grid);
      expect(result.status, GridStatus.incomplete);
      expect(result.completionRate, 0.0);
    });

    test('solved grid', () {
      final grid = Grid(
        rows: 1,
        cols: 2,
        id: 'solved',
        variant: GridVariant.standard,
        cells: [
          [
            LetterCell(solution: 'ك')..userInput = 'ك',
            LetterCell(solution: 'ل')..userInput = 'ل',
          ],
        ],
      );
      final result = validator.validateGrid(grid);
      expect(result.status, GridStatus.solved);
      expect(result.completionRate, 1.0);
    });

    test('full but wrong → GridStatus.error', () {
      final grid = Grid(
        rows: 1,
        cols: 2,
        id: 'error',
        variant: GridVariant.standard,
        cells: [
          [
            LetterCell(solution: 'ك')..userInput = 'ب', // wrong
            LetterCell(solution: 'ل')..userInput = 'ل',
          ],
        ],
      );
      final result = validator.validateGrid(grid);
      expect(result.status, GridStatus.error);
    });
  });
}
