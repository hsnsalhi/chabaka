import 'package:flutter/material.dart';

import '../../puzzle/puzzle.dart';
import '../theme/colors.dart';

/// État visuel d'une LetterCell calculé par combinaison de :
///   - sélection courante
///   - appartenance au mot actif
///   - statut de validation des mots qui couvrent la cellule
enum LetterCellVisual {
  empty, // case vide, pas dans le mot actif
  activeWord, // case du mot actif (non sélectionnée)
  selected, // case sous focus
  filled, // saisie en cours, pas dans le mot actif, pas de feedback
  correct, // au moins un mot complet et correct couvre la case
  error, // au moins un mot complet est incorrect (et la case est filled)
}

LetterCellVisual computeLetterVisual({
  required Grid grid,
  required Position cellPos,
  required LetterCell cell,
  required Position? selected,
  Direction activeDirection = Direction.horizontal,
  required GridValidationResult validation,
}) {
  final isSelected = selected == cellPos;
  final filled = (cell.userInput ?? '').trim().isNotEmpty;

  WordStatus? bestWordStatus; // priorité : correct < incorrect (incorrect gagne)
  for (final word in validation.words) {
    if (!_wordCovers(word.clue, cellPos)) continue;
    if (word.status == WordStatus.incorrect) {
      bestWordStatus = WordStatus.incorrect;
      break;
    } else if (word.status == WordStatus.correct) {
      bestWordStatus = WordStatus.correct;
    }
  }

  if (bestWordStatus == WordStatus.incorrect && filled) {
    return LetterCellVisual.error;
  }
  if (bestWordStatus == WordStatus.correct) {
    return isSelected ? LetterCellVisual.selected : LetterCellVisual.correct;
  }
  if (isSelected) return LetterCellVisual.selected;

  // "Mot actif" = même mot que la sélection DANS la direction active.
  final isInActive = selected != null &&
      _isInSameWordInDir(grid, cellPos, selected, activeDirection);
  if (isInActive) return LetterCellVisual.activeWord;

  return filled ? LetterCellVisual.filled : LetterCellVisual.empty;
}

bool _wordCovers(Clue clue, Position pos) {
  final len = clue.solution.runes.length;
  for (var i = 0; i < len; i++) {
    final p = clue.direction == Direction.horizontal
        ? Position(clue.startCell.row, clue.startCell.col + i)
        : Position(clue.startCell.row + i, clue.startCell.col);
    if (p == pos) return true;
  }
  return false;
}

bool _isInSameWordInDir(
    Grid grid, Position a, Position b, Direction dir) {
  for (final clue in grid.allClues) {
    if (clue.direction != dir) continue;
    if (_wordCovers(clue, a) && _wordCovers(clue, b)) return true;
  }
  return false;
}

/// Couleurs résolues pour un état de cellule.
class LetterCellColors {
  final Color background;
  final Color border;
  final Color text;
  final double borderWidth;

  const LetterCellColors({
    required this.background,
    required this.border,
    required this.text,
    required this.borderWidth,
  });

  factory LetterCellColors.from(LetterCellVisual visual, ColorScheme scheme) {
    switch (visual) {
      case LetterCellVisual.empty:
        return LetterCellColors(
          background: scheme.surface,
          border: scheme.outline,
          text: scheme.onSurface,
          borderWidth: 0.5,
        );
      case LetterCellVisual.filled:
        return LetterCellColors(
          background: scheme.surface,
          border: scheme.outline,
          text: scheme.onSurface,
          borderWidth: 0.5,
        );
      case LetterCellVisual.activeWord:
        return LetterCellColors(
          background: scheme.secondaryContainer,
          border: scheme.outline,
          text: scheme.onSecondaryContainer,
          borderWidth: 0.5,
        );
      case LetterCellVisual.selected:
        return LetterCellColors(
          background: scheme.primaryContainer,
          border: scheme.primary,
          text: scheme.onPrimaryContainer,
          borderWidth: 2,
        );
      case LetterCellVisual.correct:
        return const LetterCellColors(
          background: ChabakaColors.cellCorrectBg,
          border: ChabakaColors.cellCorrectFg,
          text: ChabakaColors.cellCorrectFg,
          borderWidth: 1.5,
        );
      case LetterCellVisual.error:
        return const LetterCellColors(
          background: ChabakaColors.cellErrorBg,
          border: ChabakaColors.cellErrorFg,
          text: ChabakaColors.cellErrorFg,
          borderWidth: 1.5,
        );
    }
  }
}
