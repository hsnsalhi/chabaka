import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../puzzle/puzzle.dart';
import 'cell_visuals.dart';
import 'cell_widgets.dart';
import 'puzzle_state.dart';

class GridBoard extends ConsumerWidget {
  final PuzzleState puzzle;

  const GridBoard({super.key, required this.puzzle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = puzzle.grid;
    final selected = puzzle.selected;
    final activeDir = puzzle.activeDirection;
    final validation = puzzle.validation;

    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline, width: 1),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < grid.rows; r++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c = 0; c < grid.cols; c++)
                      _buildCell(
                        grid: grid,
                        pos: Position(r, c),
                        selected: selected,
                        activeDir: activeDir,
                        validation: validation,
                      ),
                  ],
                ),
            ],
          ),
          // Flèches des indices, par-dessus les cases (débordement compris).
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: ArrowOverlayPainter(
                  grid: grid,
                  color: scheme.primary,
                  rtl: rtl,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCell({
    required Grid grid,
    required Position pos,
    required Position? selected,
    required Direction activeDir,
    required GridValidationResult validation,
  }) {
    final cell = grid.cellAt(pos);
    if (cell is ClueCell) {
      final inActive =
          selected != null &&
          _clueIsRelatedToSelected(cell, grid, selected, activeDir);
      return ClueCellWidget(cell: cell, inActiveWord: inActive);
    }
    if (cell is LetterCell) {
      final visual = computeLetterVisual(
        grid: grid,
        cellPos: pos,
        cell: cell,
        selected: selected,
        activeDirection: activeDir,
        validation: validation,
      );
      return LetterCellWidget(
        // Inclut row+col+id de la grille pour stabilité d'identité.
        key: ValueKey('cell-${grid.id}-${pos.row}-${pos.col}'),
        position: pos,
        cell: cell,
        visual: visual,
      );
    }
    return const SizedBox(width: cellSize, height: cellSize);
  }

  /// Une ClueCell est "active" si un de ses indices est sur la cellule
  /// sélectionnée DANS la direction active.
  bool _clueIsRelatedToSelected(
    ClueCell cell,
    Grid grid,
    Position selected,
    Direction activeDir,
  ) {
    for (final clue in cell.clues) {
      if (clue.direction != activeDir) continue;
      final len = clue.solution.runes.length;
      for (var i = 0; i < len; i++) {
        final p = clue.direction == Direction.horizontal
            ? Position(clue.startCell.row, clue.startCell.col + i)
            : Position(clue.startCell.row + i, clue.startCell.col);
        if (p == selected) return true;
      }
    }
    return false;
  }
}
