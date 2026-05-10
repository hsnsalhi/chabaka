import '../../puzzle/puzzle.dart';

class PuzzleState {
  final Grid grid;
  final Position? selected;
  final GridValidationResult validation;

  const PuzzleState({
    required this.grid,
    required this.selected,
    required this.validation,
  });

  PuzzleState copyWith({
    Grid? grid,
    Position? selected,
    bool clearSelected = false,
    GridValidationResult? validation,
  }) {
    return PuzzleState(
      grid: grid ?? this.grid,
      selected: clearSelected ? null : (selected ?? this.selected),
      validation: validation ?? this.validation,
    );
  }
}
