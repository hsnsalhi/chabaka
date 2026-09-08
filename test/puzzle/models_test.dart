import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/models.dart';

Grid _makeMinimalGrid() {
  return Grid(
    rows: 3,
    cols: 3,
    id: 'test-001',
    variant: GridVariant.standard,
    cells: [
      [
        ClueCell(
          clues: [
            Clue(
              text: 'اختبار',
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
      [
        LetterCell(solution: 'م'),
        LetterCell(solution: 'ل'),
        ClueCell(
          clues: [
            Clue(
              text: 'آخر',
              language: ClueLanguage.arabic,
              direction: Direction.vertical,
              solution: 'عل',
              startCell: Position(1, 2),
            ),
          ],
        ),
      ],
    ],
  );
}

void main() {
  group('Grid — basic structure', () {
    test('letterCells count', () {
      final grid = _makeMinimalGrid();
      expect(grid.letterCells.length, 7);
    });

    test('allClues count', () {
      final grid = _makeMinimalGrid();
      expect(grid.allClues.length, 2);
    });

    test('cellAt returns correct type', () {
      final grid = _makeMinimalGrid();
      expect(grid.cellAt(Position(0, 0)), isA<ClueCell>());
      expect(grid.cellAt(Position(0, 1)), isA<LetterCell>());
    });
  });

  group('Grid — JSON serialization round-trip', () {
    test('toJson / fromJson preserves all fields', () {
      final original = _makeMinimalGrid();
      final json = jsonEncode(original.toJson());
      final restored = Grid.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(restored.rows, original.rows);
      expect(restored.cols, original.cols);
      expect(restored.id, original.id);
      expect(restored.variant, original.variant);
      expect(restored.letterCells.length, 7);
      expect(restored.allClues.length, 2);
    });

    test('userInput survives round-trip', () {
      final grid = _makeMinimalGrid();
      final letterCell = grid.cells[0][1] as LetterCell;
      letterCell.userInput = 'ك';

      final json = jsonEncode(grid.toJson());
      final restored = Grid.fromJson(jsonDecode(json) as Map<String, dynamic>);
      final restoredCell = restored.cells[0][1] as LetterCell;
      expect(restoredCell.userInput, 'ك');
    });
  });

  group('Position', () {
    test('equality', () {
      expect(Position(1, 2), Position(1, 2));
      expect(Position(1, 2), isNot(Position(2, 1)));
    });

    test('JSON round-trip', () {
      const p = Position(3, 5);
      final restored = Position.fromJson(p.toJson());
      expect(restored, p);
    });
  });
}
