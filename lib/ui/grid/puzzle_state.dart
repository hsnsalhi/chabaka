import '../../puzzle/puzzle.dart';

class PuzzleState {
  final Grid grid;
  final Position? selected;

  /// Direction du mot actif (horizontal par défaut).
  /// Détermine sur quel mot porte l'auto-advance et la clue bar.
  /// Bascule H↔V en re-tapant une cellule à l'intersection.
  final Direction activeDirection;

  final GridValidationResult validation;

  const PuzzleState({
    required this.grid,
    required this.selected,
    this.activeDirection = Direction.horizontal,
    required this.validation,
  });

  PuzzleState copyWith({
    Grid? grid,
    Position? selected,
    bool clearSelected = false,
    Direction? activeDirection,
    GridValidationResult? validation,
  }) {
    return PuzzleState(
      grid: grid ?? this.grid,
      selected: clearSelected ? null : (selected ?? this.selected),
      activeDirection: activeDirection ?? this.activeDirection,
      validation: validation ?? this.validation,
    );
  }
}
