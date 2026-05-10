import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../puzzle/puzzle.dart';
import 'grid_view.dart';
import 'puzzle_providers.dart';
import 'puzzle_state.dart';

class GridScreen extends ConsumerWidget {
  const GridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPuzzle = ref.watch(puzzleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('شبكة اليوم'),
      ),
      body: asyncPuzzle.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'تحضير شبكة اليوم...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'قد يستغرق هذا بعض الوقت',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'تعذّر تحميل الشبكة\n$err',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        data: (puzzle) => _PuzzleBody(puzzle: puzzle),
      ),
    );
  }
}

class _PuzzleBody extends ConsumerWidget {
  final PuzzleState puzzle;

  const _PuzzleBody({required this.puzzle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ClueBar(
          grid: puzzle.grid,
          selected: puzzle.selected,
          activeDirection: puzzle.activeDirection,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              FocusScope.of(context).unfocus();
              ref.read(puzzleProvider.notifier).clearSelection();
            },
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.3,
              maxScale: 2.5,
              boundaryMargin: const EdgeInsets.all(80),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridBoard(puzzle: puzzle),
              ),
            ),
          ),
        ),
        _BottomFeedback(validation: puzzle.validation),
      ],
    );
  }
}

/// Affiche l'indice du mot actif (barre persistante sous l'AppBar).
/// Sans sélection : message d'invite. Avec sélection : indice + direction.
class _ClueBar extends StatelessWidget {
  final Grid grid;
  final Position? selected;
  final Direction activeDirection;

  const _ClueBar({
    required this.grid,
    required this.selected,
    required this.activeDirection,
  });

  Clue? _findActiveClue() {
    if (selected == null) return null;
    // Priorité : direction active. Fallback : l'autre.
    final order = activeDirection == Direction.horizontal
        ? [Direction.horizontal, Direction.vertical]
        : [Direction.vertical, Direction.horizontal];
    for (final dir in order) {
      for (final clue in grid.allClues) {
        if (clue.direction != dir) continue;
        final len = clue.solution.runes.length;
        for (var i = 0; i < len; i++) {
          final p = clue.direction == Direction.horizontal
              ? Position(clue.startCell.row, clue.startCell.col + i)
              : Position(clue.startCell.row + i, clue.startCell.col);
          if (p == selected) return clue;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final clue = _findActiveClue();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: clue != null
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    clue.text,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  clue.direction == Direction.horizontal ? '←' : '↓',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    height: 1.0,
                  ),
                ),
              ],
            )
          : Text(
              'اختر حقلاً لقراءة الدليل',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
    );
  }
}

class _BottomFeedback extends StatelessWidget {
  final GridValidationResult validation;

  const _BottomFeedback({required this.validation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String message;
    Color background;
    Color foreground;

    switch (validation.status) {
      case GridStatus.solved:
        message = '✓  أحسنت ! أنهيت شبكة اليوم بنجاح';
        background = scheme.primary;
        foreground = scheme.onPrimary;
      case GridStatus.error:
        message = '✗  توجد أخطاء — راجع الشبكة';
        background = scheme.errorContainer.withValues(alpha: 1.0);
        foreground = scheme.error;
      case GridStatus.incomplete:
        final pct = (validation.completionRate * 100).toInt();
        message = 'تقدّمك : $pct٪';
        background = scheme.surfaceContainerHighest;
        foreground = scheme.onSurface;
    }

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: background,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }
}
