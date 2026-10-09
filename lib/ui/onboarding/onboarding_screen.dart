import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/persistence/settings_service.dart';
import '../../ui/common/arabesque_background.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

// ── Modèle de page ─────────────────────────────────────────────────────────

class _OnboardingPage {
  final String title;
  final String subtitle;
  final Widget illustration;
  final String semanticLabel;

  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.semanticLabel,
  });
}

// ── Écran ─────────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static final _pages = <_OnboardingPage>[
    _OnboardingPage(
      title: 'ما هي شبكة المسهمة ؟',
      subtitle: 'شبكة كلمات مسهمة عربية على طريقة الجرائد\nبلا مربعات سوداء: الأسهم تحدد اتجاه الكلمات',
      illustration: const _IllustrationGrid(),
      semanticLabel: 'شرح تنسيق شبكة المسهمة',
    ),
    _OnboardingPage(
      title: 'أنواع الأسهم الأربعة',
      subtitle: 'كل سهم يشير إلى اتجاه الإجابة\nداخل الشبكة',
      illustration: const _IllustrationArrows(),
      semanticLabel: 'شرح الأسهم الأربعة المستخدمة في الشبكة',
    ),
    _OnboardingPage(
      title: 'النقاط والسلسلة',
      subtitle: 'أكمل شبكة كل يوم وحافظ على سلسلتك\nلتفتح الإنجازات',
      illustration: const _IllustrationStreak(),
      semanticLabel: 'شرح نظام النقاط والسلسلة اليومية',
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await ref.read(onboardingDoneProvider.notifier).markDone();
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ArabesqueBackground(opacity: 0.04),
          SafeArea(
            child: Column(
              children: [
                // Bouton "Passer"
                Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 16, top: 8),
                    child: Semantics(
                      label: 'تخطي مقدمة التطبيق',
                      child: TextButton(
                        onPressed: _finish,
                        child: Text(
                          'تخطي',
                          style: ChabakaTextStyles.label.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (context, i) =>
                        _OnboardingPageView(page: _pages[i]),
                  ),
                ),
                // Indicateur + bouton
                _BottomControls(
                  pageCount: _pages.length,
                  currentPage: _currentPage,
                  isLast: isLast,
                  onNext: _nextPage,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page individuelle ─────────────────────────────────────────────────────────

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;

  const _OnboardingPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: page.semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration
            SizedBox(height: 220, child: page.illustration),
            const SizedBox(height: 40),
            // Titre
            Text(
              page.title,
              textAlign: TextAlign.center,
              style: ChabakaTextStyles.h2.copyWith(
                color: ChabakaColors.bordeaux,
              ),
            ),
            const SizedBox(height: 16),
            // Description
            Text(
              page.subtitle,
              textAlign: TextAlign.center,
              style: ChabakaTextStyles.body.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contrôles bas de page ─────────────────────────────────────────────────────

class _BottomControls extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final bool isLast;
  final VoidCallback onNext;

  const _BottomControls({
    required this.pageCount,
    required this.currentPage,
    required this.isLast,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicateur dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pageCount, (i) {
              final active = i == currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? ChabakaColors.bordeaux
                      : ChabakaColors.bordeaux.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          // Bouton principal
          Semantics(
            label: isLast ? 'ابدأ اللعب' : 'الصفحة التالية',
            button: true,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChabakaColors.bordeaux,
                  foregroundColor: ChabakaColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isLast ? 'ابدأ الآن' : 'التالي',
                  style: ChabakaTextStyles.labelLarge.copyWith(
                    color: ChabakaColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Illustrations ─────────────────────────────────────────────────────────────

/// Mini grille 4×3 illustrant le format مسهمة
class _IllustrationGrid extends StatelessWidget {
  const _IllustrationGrid();

  @override
  Widget build(BuildContext context) {
    const cellSize = 44.0;
    const cells = [
      // row 0 : CC=bloqueur, LC, LC, LC
      [false, true, true, true],
      // row 1 : CC, CC, LC, LC
      [false, false, true, true],
      // row 2 : CC, LC, LC, CC
      [false, true, true, false],
    ];
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(cells.length, (r) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(cells[r].length, (c) {
                final isLC = cells[r][c];
                return _MiniCell(
                  size: cellSize,
                  isLetterCell: isLC,
                  letter: isLC ? _sampleLetters[r * 4 + c] : '',
                  isCC: !isLC,
                );
              }),
            );
          }),
        ),
      ),
    );
  }

  static const _sampleLetters = [
    '',
    'ك',
    'ت',
    'ب',
    '',
    '',
    'ع',
    'ر',
    '',
    'ب',
    'ي',
    '',
  ];
}

class _MiniCell extends StatelessWidget {
  final double size;
  final bool isLetterCell;
  final String letter;
  final bool isCC;

  const _MiniCell({
    required this.size,
    required this.isLetterCell,
    required this.letter,
    required this.isCC,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isCC
            ? ChabakaColors.brunChaud.withValues(alpha: 0.15)
            : scheme.surface,
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: isLetterCell
          ? Center(
              child: Text(
                letter,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: ChabakaColors.bordeaux,
                ),
              ),
            )
          : Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    '←',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 10,
                      color: ChabakaColors.bordeaux.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Illustration des 4 types de flèches
class _IllustrationArrows extends StatelessWidget {
  const _IllustrationArrows();

  @override
  Widget build(BuildContext context) {
    const arrows = [
      ('←', 'أفقي من اليمين'),
      ('↓', 'عمودي نحو الأسفل'),
      ('↲', 'أفقي + نزول'),
      ('↴', 'عمودي + يمين'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 16,
      children: arrows
          .map((a) => _ArrowCard(arrow: a.$1, label: a.$2))
          .toList(),
    );
  }
}

class _ArrowCard extends StatelessWidget {
  final String arrow;
  final String label;

  const _ArrowCard({required this.arrow, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            arrow,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 32,
              color: ChabakaColors.bordeaux,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: ChabakaTextStyles.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Illustration streak — flamme + compteur
class _IllustrationStreak extends StatelessWidget {
  const _IllustrationStreak();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Flamme
        const Text('🔥', style: TextStyle(fontSize: 72)),
        const SizedBox(height: 16),
        // Compteur
        Text(
          '٧ أيام',
          textDirection: TextDirection.rtl,
          style: ChabakaTextStyles.h2.copyWith(color: ChabakaColors.bordeaux),
        ),
        const SizedBox(height: 8),
        // Barre de progression simulée
        _StreakBar(),
      ],
    );
  }
}

class _StreakBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final done = i < 5;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? ChabakaColors.bordeaux
                : ChabakaColors.bordeaux.withValues(alpha: 0.15),
          ),
          child: Icon(
            done ? Icons.check : null,
            size: 16,
            color: ChabakaColors.white,
          ),
        );
      }),
    );
  }
}
