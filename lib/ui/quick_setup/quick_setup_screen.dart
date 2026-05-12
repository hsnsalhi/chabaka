/// Écran de sélection mode rapide.
///
/// Layout RTL :
///   1. Header "اختر مستواك"
///   2. 4 cartes Difficulty (radio-style, staggered animation)
///   3. Section "الفئات" (chips multi-select scrollables)
///   4. Bottom bar fixe : preview + bouton "بدء اللعبة"
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/game/game_options.dart';
import '../../ui/grid/puzzle_providers.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

// ---------------------------------------------------------------------------
// Providers locaux
// ---------------------------------------------------------------------------

/// Difficulté sélectionnée dans l'écran de setup.
final _selectedDifficultyProvider = StateProvider<Difficulty>(
  (_) => Difficulty.intermediate,
);

/// Thèmes sélectionnés (ensemble de clés SQL).
final _selectedThemesProvider = StateProvider<Set<String>>((_) => {});

/// Nombre de mots dispo pour les thèmes sélectionnés.
final _wordCountProvider = FutureProvider<int>((ref) async {
  final themes = ref.watch(_selectedThemesProvider);
  if (themes.isEmpty) {
    // Tous thèmes → compte total.
    final kb = await ref.watch(kbRepositoryProvider.future);
    return kb.countEntries();
  }
  final kb = await ref.watch(kbRepositoryProvider.future);
  return kb.countMatchingCategories(themes);
});

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

/// Seuil minimum de mots pour considérer la sélection viable.
const _kMinWords = 200;

// ---------------------------------------------------------------------------
// Écran principal
// ---------------------------------------------------------------------------

class QuickSetupScreen extends ConsumerWidget {
  const QuickSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header
                SliverToBoxAdapter(child: _Header()),
                // Cartes Difficulty
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _StaggeredDifficultyCard(
                        difficulty: Difficulty.values[i],
                        index: i,
                      ),
                      childCount: Difficulty.values.length,
                    ),
                  ),
                ),
                // Section catégories
                SliverToBoxAdapter(child: _ThemesSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          // Bottom bar fixe
          _BottomBar(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Row(
          children: [
            Semantics(
              label: 'عودة',
              button: true,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_forward_ios, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'اختر مستواك',
                style: ChabakaTextStyles.h2.copyWith(
                  color: scheme.onSurface,
                  fontSize: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cartes difficulté avec animation staggered
// ---------------------------------------------------------------------------

class _StaggeredDifficultyCard extends StatefulWidget {
  final Difficulty difficulty;
  final int index;

  const _StaggeredDifficultyCard({
    required this.difficulty,
    required this.index,
  });

  @override
  State<_StaggeredDifficultyCard> createState() => _StaggeredDifficultyCardState();
}

class _StaggeredDifficultyCardState extends State<_StaggeredDifficultyCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _DifficultyCard(difficulty: widget.difficulty),
        ),
      ),
    );
  }
}

class _DifficultyCard extends ConsumerStatefulWidget {
  final Difficulty difficulty;

  const _DifficultyCard({required this.difficulty});

  @override
  ConsumerState<_DifficultyCard> createState() => _DifficultyCardState();
}

class _DifficultyCardState extends ConsumerState<_DifficultyCard> {
  bool _pressed = false;

  Color _accentColor() => switch (widget.difficulty) {
        Difficulty.beginner => const Color(0xFF10B981),     // vert
        Difficulty.intermediate => const Color(0xFFF59E0B), // ambre
        Difficulty.expert => const Color(0xFFEF6C00),       // orange
        Difficulty.master => const Color(0xFFDC2626),       // rouge
      };

  String _emoji() => switch (widget.difficulty) {
        Difficulty.beginner => '🟢',
        Difficulty.intermediate => '🟡',
        Difficulty.expert => '🟠',
        Difficulty.master => '🔴',
      };

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(_selectedDifficultyProvider);
    final isSelected = selected == widget.difficulty;
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentColor();

    return Semantics(
      label: '${widget.difficulty.labelAr} — ${widget.difficulty.subtitleAr}',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.selectionClick();
          ref.read(_selectedDifficultyProvider.notifier).state =
              widget.difficulty;
          // Si la difficulté a un max thèmes, ajuster les thèmes sélectionnés.
          final maxT = widget.difficulty.maxThemes;
          if (maxT != null) {
            final current = ref.read(_selectedThemesProvider);
            if (current.length > maxT) {
              ref.read(_selectedThemesProvider.notifier).state =
                  current.take(maxT).toSet();
            }
          }
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.08)
                  : scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? accent
                    : scheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Text(_emoji(), style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.difficulty.labelAr,
                        style: ChabakaTextStyles.label.copyWith(
                          color: isSelected ? accent : scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.difficulty.subtitleAr,
                        style: ChabakaTextStyles.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section thèmes
// ---------------------------------------------------------------------------

class _ThemesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final difficulty = ref.watch(_selectedDifficultyProvider);
    final selectedThemes = ref.watch(_selectedThemesProvider);
    final scheme = Theme.of(context).colorScheme;
    final maxThemes = difficulty.maxThemes;

    // Master : exactement 1 thème obligatoire
    // Expert : max 2
    // Beginner/Intermediate : illimité

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'الفئات',
                style: ChabakaTextStyles.h3.copyWith(
                  color: scheme.onSurface,
                  fontSize: 20,
                ),
              ),
              const SizedBox(width: 8),
              if (maxThemes != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ChabakaColors.or.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'حد أقصى $maxThemes',
                    style: ChabakaTextStyles.caption.copyWith(
                      color: ChabakaColors.orMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selectedThemes.isEmpty
                ? 'جميع الفئات مختارة'
                : 'اختر الفئات التي تريد اللعب بها',
            style: ChabakaTextStyles.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 12),
          // Chips scrollables horizontalement — RTL
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            reverse: true, // RTL : départ à droite
            child: Row(
              children: [
                // Chip "الكل"
                _ThemeChip(
                  label: 'الكل',
                  isSelected: selectedThemes.isEmpty,
                  onTap: () {
                    ref.read(_selectedThemesProvider.notifier).state = {};
                  },
                ),
                const SizedBox(width: 8),
                // Chips catégories
                ...kCategoryLabels.entries.map((entry) {
                  final key = entry.key;
                  final label = entry.value;
                  final isSelected = selectedThemes.contains(key);
                  final isDisabled = !isSelected &&
                      maxThemes != null &&
                      selectedThemes.length >= maxThemes;

                  return Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: _ThemeChip(
                      label: label,
                      isSelected: isSelected,
                      isDisabled: isDisabled,
                      onTap: isDisabled
                          ? null
                          : () {
                              final current =
                                  ref.read(_selectedThemesProvider);
                              final updated = Set<String>.of(current);
                              if (isSelected) {
                                updated.remove(key);
                              } else {
                                updated.add(key);
                              }
                              ref
                                  .read(_selectedThemesProvider.notifier)
                                  .state = updated;
                            },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Compteur de mots
          _WordCountBadge(),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _ThemeChip({
    required this.label,
    required this.isSelected,
    this.isDisabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      enabled: !isDisabled,
      child: GestureDetector(
        onTap: onTap != null
            ? () {
                HapticFeedback.selectionClick();
                onTap!();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? ChabakaColors.indigo
                : isDisabled
                    ? scheme.surfaceContainerHighest
                    : scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? ChabakaColors.indigo
                  : scheme.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: ChabakaTextStyles.caption.copyWith(
              color: isSelected
                  ? ChabakaColors.white
                  : isDisabled
                      ? scheme.onSurface.withValues(alpha: 0.35)
                      : scheme.onSurface,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _WordCountBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(_wordCountProvider);
    final scheme = Theme.of(context).colorScheme;

    return countAsync.when(
      loading: () => const SizedBox(height: 24),
      error: (_, __) => const SizedBox.shrink(),
      data: (count) {
        final isTight = count < _kMinWords;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isTight
                ? ChabakaColors.error.withValues(alpha: 0.1)
                : ChabakaColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isTight
                  ? ChabakaColors.error.withValues(alpha: 0.3)
                  : ChabakaColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTight ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                size: 16,
                color: isTight ? ChabakaColors.error : ChabakaColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                isTight
                    ? 'ضيق جداً — $count كلمة فقط'
                    : '$count كلمة متاحة',
                style: ChabakaTextStyles.caption.copyWith(
                  color: isTight
                      ? ChabakaColors.error
                      : scheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class _BottomBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final difficulty = ref.watch(_selectedDifficultyProvider);
    final themes = ref.watch(_selectedThemesProvider);
    final countAsync = ref.watch(_wordCountProvider);

    final wordCount = countAsync.valueOrNull ?? 0;
    final isTight = wordCount < _kMinWords && countAsync.hasValue;

    // Validation spécifique au niveau master.
    final isMasterWithoutTheme =
        difficulty == Difficulty.master && themes.isEmpty;
    final isValid = !isTight && !isMasterWithoutTheme;

    final (rows, cols) = difficulty.gridSize;
    final themeLabel = themes.isEmpty
        ? 'جميع الفئات'
        : themes.map((k) => kCategoryLabels[k] ?? k).join('، ');

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview
            Text(
              '$rows×$cols — $themeLabel',
              textAlign: TextAlign.center,
              style: ChabakaTextStyles.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (isMasterWithoutTheme) ...[
              const SizedBox(height: 4),
              Text(
                'مستوى الأستاذ يتطلب اختيار فئة واحدة',
                textAlign: TextAlign.center,
                style: ChabakaTextStyles.caption.copyWith(
                  color: ChabakaColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Bouton principal
            Semantics(
              button: true,
              enabled: isValid,
              label: 'بدء اللعبة',
              child: ElevatedButton(
                onPressed: isValid
                    ? () {
                        HapticFeedback.mediumImpact();
                        final opts = GameOptions.quick(
                          difficulty: difficulty,
                          themes: themes,
                        );
                        context.push(AppRoutes.gameQuick, extra: opts);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChabakaColors.indigo,
                  disabledBackgroundColor:
                      scheme.onSurface.withValues(alpha: 0.12),
                  foregroundColor: ChabakaColors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'بدء اللعبة',
                  style: ChabakaTextStyles.labelLarge.copyWith(
                    color: isValid
                        ? ChabakaColors.white
                        : scheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
