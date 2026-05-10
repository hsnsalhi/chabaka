/// Validation de la progression sur la grille مسهمة.

import 'arabic_normalizer.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Résultats de validation
// ---------------------------------------------------------------------------

enum WordStatus {
  empty,       // aucune lettre saisie
  partial,     // en cours de saisie
  correct,     // mot terminé et correct
  incorrect,   // mot terminé mais incorrect
}

enum GridStatus {
  incomplete,
  solved,
  error, // complète mais avec des erreurs
}

class WordValidationResult {
  final Clue clue;
  final WordStatus status;
  final List<bool?> letterResults; // null=vide, true=correct, false=incorrect

  const WordValidationResult({
    required this.clue,
    required this.status,
    required this.letterResults,
  });
}

class GridValidationResult {
  final GridStatus status;
  final List<WordValidationResult> words;
  final int totalLetters;
  final int filledLetters;
  final int correctLetters;

  const GridValidationResult({
    required this.status,
    required this.words,
    required this.totalLetters,
    required this.filledLetters,
    required this.correctLetters,
  });

  double get completionRate =>
      totalLetters == 0 ? 0.0 : filledLetters / totalLetters;
}

// ---------------------------------------------------------------------------
// Validator
// ---------------------------------------------------------------------------

class GridValidator {
  final ArabicNormalizer normalizer;

  const GridValidator({
    this.normalizer = const ArabicNormalizer(),
  });

  /// Valide un seul mot (Clue) contre l'état courant de la grille.
  WordValidationResult validateWord(Grid grid, Clue clue) {
    final solution = normalizer.normalize(clue.solution);
    final letters = _extractLetters(grid, clue);

    if (letters.every((l) => l == null)) {
      return WordValidationResult(
        clue: clue,
        status: WordStatus.empty,
        letterResults: List.filled(letters.length, null),
      );
    }

    final results = <bool?>[];
    var allFilled = true;
    var allCorrect = true;

    for (var i = 0; i < letters.length; i++) {
      final userLetter = letters[i];
      if (userLetter == null || userLetter.trim().isEmpty) {
        results.add(null);
        allFilled = false;
        allCorrect = false;
      } else {
        final solutionLetter =
            i < solution.length ? solution[i] : ''; // caractère attendu
        final isCorrect = normalizer.matchesLetter(userLetter, solutionLetter);
        results.add(isCorrect);
        if (!isCorrect) allCorrect = false;
      }
    }

    final status = switch ((allFilled, allCorrect)) {
      (true, true) => WordStatus.correct,
      (true, false) => WordStatus.incorrect,
      _ => WordStatus.partial,
    };

    return WordValidationResult(
      clue: clue,
      status: status,
      letterResults: results,
    );
  }

  /// Valide la grille complète.
  GridValidationResult validateGrid(Grid grid) {
    final wordResults = grid.allClues
        .map((clue) => validateWord(grid, clue))
        .toList();

    var total = 0;
    var filled = 0;
    var correct = 0;

    for (final entry in grid.letterCells) {
      total++;
      final input = entry.cell.userInput;
      if (input != null && input.trim().isNotEmpty) {
        filled++;
        if (normalizer.matchesLetter(input, entry.cell.solution)) {
          correct++;
        }
      }
    }

    final gridStatus = switch ((total == filled, total == correct)) {
      (true, true) => GridStatus.solved,
      (true, false) => GridStatus.error,
      _ => GridStatus.incomplete,
    };

    return GridValidationResult(
      status: gridStatus,
      words: wordResults,
      totalLetters: total,
      filledLetters: filled,
      correctLetters: correct,
    );
  }

  // Extrait les userInput des LetterCell couverts par un mot.
  List<String?> _extractLetters(Grid grid, Clue clue) {
    final letters = <String?>[];
    final len = clue.solution.runes.length; // longueur en caractères arabes

    for (var i = 0; i < len; i++) {
      final pos = clue.direction == Direction.horizontal
          ? Position(clue.startCell.row, clue.startCell.col + i)
          : Position(clue.startCell.row + i, clue.startCell.col);

      if (pos.row >= grid.rows || pos.col >= grid.cols) break;

      final cell = grid.cellAt(pos);
      letters.add(cell is LetterCell ? cell.userInput : null);
    }

    return letters;
  }
}
