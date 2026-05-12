import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/achievements/achievement_service.dart';
import '../../data/score/score_service.dart';
import '../../data/score/streak_service.dart';
import '../../puzzle/puzzle.dart';
import '../../ui/grid/grid_view.dart';
import '../../ui/grid/puzzle_providers.dart';
import '../../ui/grid/puzzle_state.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

// ── État de session de jeu ─────────────────────────────────────────────────────

class GameSessionState {
  final int hintsUsed;
  final int errorsChecked;
  final bool checkDone; // si l'utilisateur a tapé "check" au moins une fois

  const GameSessionState({
    this.hintsUsed = 0,
    this.errorsChecked = 0,
    this.checkDone = false,
  });

  GameSessionState copyWith({int? hintsUsed, int? errorsChecked, bool? checkDone}) =>
      GameSessionState(
        hintsUsed: hintsUsed ?? this.hintsUsed,
        errorsChecked: errorsChecked ?? this.errorsChecked,
        checkDone: checkDone ?? this.checkDone,
      );
}

class GameSessionNotifier extends Notifier<GameSessionState> {
  @override
  GameSessionState build() => const GameSessionState();

  void useHint() => state = state.copyWith(hintsUsed: state.hintsUsed + 1);
  void addErrors(int count) =>
      state = state.copyWith(errorsChecked: state.errorsChecked + count, checkDone: true);
  void reset() => state = const GameSessionState();
}

final gameSessionProvider =
    NotifierProvider<GameSessionNotifier, GameSessionState>(GameSessionNotifier.new);

// ── Screen principal ───────────────────────────────────────────────────────────

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  bool _completionHandled = false;

  @override
  void initState() {
    super.initState();
    // Démarre le timer quand l'écran s'ouvre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(timerProvider.notifier).start();
      ref.read(gameSessionProvider.notifier).reset();
      ref.read(currentScoreProvider.notifier).reset();
      _completionHandled = false;
    });
  }

  @override
  void dispose() {
    // Le timer continue si on revient (pas de reset ici, reset à l'initState).
    super.dispose();
  }

  void _checkCompletion(PuzzleState puzzle) {
    if (_completionHandled) return;
    if (puzzle.validation.status != GridStatus.solved) return;

    _completionHandled = true;
    _handleCompletion(puzzle);
  }

  Future<void> _handleCompletion(PuzzleState puzzle) async {
    ref.read(timerProvider.notifier).stop();
    final timer = ref.read(timerProvider);
    final session = ref.read(gameSessionProvider);
    final scoreService = ref.read(scoreServiceProvider);
    final streakService = ref.read(streakServiceProvider);
    final achievementService = ref.read(achievementServiceProvider);

    final finalScore = ScoreCalculator.calculate(
      timeMs: timer.elapsed.inMilliseconds,
      hintsUsed: session.hintsUsed,
      errorsCount: session.errorsChecked,
    );

    // Sauvegarde du score.
    await scoreService.saveScore(GameScore(
      gridId: puzzle.grid.id,
      score: finalScore,
      timeMs: timer.elapsed.inMilliseconds,
      hintsUsed: session.hintsUsed,
      errorsCount: session.errorsChecked,
      completedAt: DateTime.now(),
    ));

    // Streak.
    final newStreak = await streakService.recordCompletion();
    ref.read(streakProvider.notifier).setStreak(newStreak);

    // Achievements.
    final totalGames = scoreService.totalGamesPlayed;
    final newAchievements = await achievementService.checkAfterCompletion(
      totalGamesCompleted: totalGames,
      hintsUsed: session.hintsUsed,
      streak: newStreak,
    );

    if (!mounted) return;

    // Navigation vers /result avec les paramètres.
    context.go(
      AppRoutes.result,
      extra: ResultArgs(
        score: finalScore,
        timeMs: timer.elapsed.inMilliseconds,
        hintsUsed: session.hintsUsed,
        errorsCount: session.errorsChecked,
        newAchievements: newAchievements,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncPuzzle = ref.watch(puzzleProvider);

    // Détection de completion reactive.
    ref.listen<AsyncValue<PuzzleState>>(puzzleProvider, (_, next) {
      next.whenData(_checkCompletion);
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: asyncPuzzle.when(
        loading: () => const _LoadingView(),
        error: (err, _) => _ErrorView(message: err.toString()),
        data: (puzzle) => _GameBody(puzzle: puzzle),
      ),
    );
  }
}

// ── Vue de chargement ──────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
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
    );
  }
}

// ── Vue d'erreur ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'تعذّر تحميل الشبكة',
                style: ChabakaTextStyles.h3.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: ChabakaTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Corps principal du jeu ──────────────────────────────────────────────────────

class _GameBody extends ConsumerWidget {
  final PuzzleState puzzle;

  const _GameBody({required this.puzzle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _StickyHeader(puzzle: puzzle),
        Expanded(
          child: _ZoomableGrid(puzzle: puzzle),
        ),
        _StickyFooter(puzzle: puzzle),
      ],
    );
  }
}

// ── Header sticky ──────────────────────────────────────────────────────────────

class _StickyHeader extends ConsumerWidget {
  final PuzzleState puzzle;

  const _StickyHeader({required this.puzzle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final timer = ref.watch(timerProvider);
    final score = ref.watch(currentScoreProvider);
    final completion = puzzle.validation.completionRate;

    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre principale
          Container(
            height: 56,
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 16, 0),
            color: scheme.surface,
            child: Row(
              children: [
                // Bouton retour
                Semantics(
                  label: 'العودة للقائمة الرئيسية',
                  button: true,
                  child: IconButton(
                    onPressed: () {
                      ref.read(timerProvider.notifier).stop();
                      context.go(AppRoutes.home);
                    },
                    icon: const Icon(Icons.arrow_forward_ios, size: 20),
                    tooltip: 'عودة',
                  ),
                ),
                // Timer centré
                Expanded(
                  child: Center(
                    child: _AnimatedTimer(formatted: timer.formatted),
                  ),
                ),
                // Score
                _ScoreChip(score: score),
              ],
            ),
          ),
          // Progress bar
          _ProgressBar(completion: completion),
        ],
      ),
    );
  }
}

class _AnimatedTimer extends StatelessWidget {
  final String formatted;

  const _AnimatedTimer({required this.formatted});

  @override
  Widget build(BuildContext context) {
    return Text(
      formatted,
      textDirection: TextDirection.ltr,
      style: ChabakaTextStyles.label.copyWith(
        fontFamily: 'Cairo',
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: Theme.of(context).colorScheme.onSurface,
        letterSpacing: 2,
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final int score;

  const _ScoreChip({required this.score});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'النقاط الحالية: $score',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ChabakaColors.bordeaux.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ChabakaColors.bordeaux.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          score.toString(),
          textDirection: TextDirection.ltr,
          style: ChabakaTextStyles.label.copyWith(
            color: ChabakaColors.bordeaux,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double completion;

  const _ProgressBar({required this.completion});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: completion,
        backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
        valueColor: AlwaysStoppedAnimation<Color>(ChabakaColors.bordeaux),
        minHeight: 3,
      ),
    );
  }
}

// ── Grille zoomable ─────────────────────────────────────────────────────────────

class _ZoomableGrid extends ConsumerWidget {
  final PuzzleState puzzle;

  const _ZoomableGrid({required this.puzzle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
        ref.read(puzzleProvider.notifier).clearSelection();
      },
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.6,
        maxScale: 3.0,
        boundaryMargin: const EdgeInsets.all(80),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GridBoard(puzzle: puzzle),
        ),
      ),
    );
  }
}

// ── Footer sticky ──────────────────────────────────────────────────────────────

class _StickyFooter extends ConsumerWidget {
  final PuzzleState puzzle;

  const _StickyFooter({required this.puzzle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(gameSessionProvider);

    // Nombre de LCs vides (pour désactiver le hint).
    final emptyLcs = puzzle.grid.letterCells
        .where((e) => (e.cell.userInput ?? '').isEmpty)
        .length;
    final hintAvailable = emptyLcs > 0;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Clue actif
          _ActiveClueBar(puzzle: puzzle),
          // Barre de boutons
          Container(
            height: 60,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                top: BorderSide(color: scheme.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Hint button
                _FooterButton(
                  icon: Icons.lightbulb_outline,
                  label: 'تلميح  -50',
                  enabled: hintAvailable,
                  color: ChabakaColors.or,
                  onPressed: hintAvailable
                      ? () => _useHint(context, ref, puzzle)
                      : null,
                ),
                // Check button
                _FooterButton(
                  icon: Icons.check_circle_outline,
                  label: 'تحقق',
                  enabled: true,
                  color: ChabakaColors.bordeaux,
                  onPressed: () => _checkGrid(context, ref, puzzle, session),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _useHint(BuildContext context, WidgetRef ref, PuzzleState puzzle) {
    // Trouver une LC vide aléatoire et la révéler.
    final empties = puzzle.grid.letterCells
        .where((e) => (e.cell.userInput ?? '').isEmpty)
        .toList();
    if (empties.isEmpty) return;

    final rng = math.Random();
    final pick = empties[rng.nextInt(empties.length)];
    ref.read(puzzleProvider.notifier).setLetter(pick.pos, pick.cell.solution);
    ref.read(gameSessionProvider.notifier).useHint();
    ref.read(currentScoreProvider.notifier).applyHint();

    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم الكشف عن حرف (-50 نقطة)',
          style: ChabakaTextStyles.bodySmall.copyWith(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: ChabakaColors.or,
      ),
    );
  }

  void _checkGrid(
    BuildContext context,
    WidgetRef ref,
    PuzzleState puzzle,
    GameSessionState session,
  ) {
    final validation = puzzle.validation;
    final errors = validation.words
        .where((w) => w.status == WordStatus.incorrect)
        .length;

    if (errors > 0) {
      ref.read(gameSessionProvider.notifier).addErrors(errors);
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'توجد $errors أخطاء — راجع الشبكة',
            style: ChabakaTextStyles.bodySmall.copyWith(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: ChabakaColors.error,
        ),
      );
    } else if (validation.status == GridStatus.incomplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا أخطاء حتى الآن — واصل !',
            style: ChabakaTextStyles.bodySmall.copyWith(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: ChabakaColors.success,
        ),
      );
    }
  }
}

class _FooterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback? onPressed;

  const _FooterButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled
        ? color
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveColor, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: ChabakaTextStyles.caption.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Clue actif (expanded tooltip) ─────────────────────────────────────────────

class _ActiveClueBar extends StatelessWidget {
  final PuzzleState puzzle;

  const _ActiveClueBar({required this.puzzle});

  Clue? _findActiveClue() {
    final selected = puzzle.selected;
    if (selected == null) return null;
    final order = puzzle.activeDirection == Direction.horizontal
        ? [Direction.horizontal, Direction.vertical]
        : [Direction.vertical, Direction.horizontal];
    for (final dir in order) {
      for (final clue in puzzle.grid.allClues) {
        if (clue.direction != dir) continue;
        final len = clue.solution.runes.length;
        for (var i = 0; i < len; i++) {
          final p = dir == Direction.horizontal
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
    final scheme = Theme.of(context).colorScheme;
    final clue = _findActiveClue();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 80),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: clue != null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    clue.text,
                    style: ChabakaTextStyles.body.copyWith(
                      fontSize: 16,
                      height: 1.4,
                      color: scheme.onSurface,
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
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ChabakaColors.bordeaux,
                    height: 1.0,
                  ),
                ),
              ],
            )
          : Text(
              'اختر حقلاً لقراءة الدليل',
              style: ChabakaTextStyles.bodySmall.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
    );
  }
}

// ── Paramètres passés à ResultScreen ──────────────────────────────────────────

class ResultArgs {
  final int score;
  final int timeMs;
  final int hintsUsed;
  final int errorsCount;
  final List<dynamic> newAchievements;

  const ResultArgs({
    required this.score,
    required this.timeMs,
    required this.hintsUsed,
    required this.errorsCount,
    required this.newAchievements,
  });
}
