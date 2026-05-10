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
