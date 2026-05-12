import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/score/streak_service.dart';
import '../../ui/common/arabesque_background.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

// ── Modèle carte ─────────────────────────────────────────────────────────────

class _MenuCard {
  final String icon;
  final String title;
  final String subtitle;
  final String route;
  final bool isPrimary;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.isPrimary = false,
  });
}

const _cards = <_MenuCard>[
  _MenuCard(
    icon: '🎯',
    title: 'شبكة اليوم',
    subtitle: 'شبكة مسهمة جديدة كل يوم',
    route: AppRoutes.gameDaily,
    isPrimary: true,
  ),
  _MenuCard(
    icon: '⚡',
    title: 'لعبة سريعة',
    subtitle: 'اختر مستواك وابدأ فوراً',
    route: AppRoutes.quickSetup,
  ),
  _MenuCard(
    icon: '📅',
    title: 'التقويم',
    subtitle: 'استعرض شبكات الأيام الماضية',
    route: AppRoutes.home, // Phase B
  ),
  _MenuCard(
    icon: '📊',
    title: 'الإحصائيات',
    subtitle: 'تقدّمك ومعدلات الإنجاز',
    route: AppRoutes.stats,
  ),
  _MenuCard(
    icon: '⚙️',
    title: 'الإعدادات',
    subtitle: 'المظهر، الصوت، اللغة',
    route: AppRoutes.settings,
  ),
];

// ── Écran ─────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ArabesqueBackground(opacity: 0.04),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header
                SliverToBoxAdapter(child: _Header()),
                // Divider
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Divider(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      height: 1,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                // Cartes menu avec staggered delay
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _StaggeredCard(
                        card: _cards[i],
                        index: i,
                      ),
                      childCount: _cards.length,
                    ),
                  ),
                ),
                // Footer
                SliverToBoxAdapter(
                  child: _Footer(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'شبكة',
                  textDirection: TextDirection.rtl,
                  style: ChabakaTextStyles.h1.copyWith(
                    color: ChabakaColors.bordeaux,
                    fontSize: 52,
                  ),
                ),
                Text(
                  'مسهمة عربية يومية',
                  textDirection: TextDirection.rtl,
                  style: ChabakaTextStyles.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (streak > 0) ...[
            const SizedBox(width: 16),
            _StreakBadge(streak: streak),
          ],
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int streak;

  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'السلسلة الحالية: $streak يوم',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ChabakaColors.bordeaux.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ChabakaColors.bordeaux.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 2),
            Text(
              '$streak',
              style: ChabakaTextStyles.label.copyWith(
                color: ChabakaColors.bordeaux,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Carte menu avec animation staggered ──────────────────────────────────────

class _StaggeredCard extends StatefulWidget {
  final _MenuCard card;
  final int index;

  const _StaggeredCard({required this.card, required this.index});

  @override
  State<_StaggeredCard> createState() => _StaggeredCardState();
}

class _StaggeredCardState extends State<_StaggeredCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    // Délai staggered : 50ms * index
    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
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
          child: _MenuCardWidget(card: widget.card),
        ),
      ),
    );
  }
}

// ── Widget carte ──────────────────────────────────────────────────────────────

class _MenuCardWidget extends StatefulWidget {
  final _MenuCard card;

  const _MenuCardWidget({required this.card});

  @override
  State<_MenuCardWidget> createState() => _MenuCardWidgetState();
}

class _MenuCardWidgetState extends State<_MenuCardWidget> {
  bool _pressed = false;

  void _onTap(BuildContext context) {
    HapticFeedback.lightImpact();
    context.push(widget.card.route);
  }

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.card.isPrimary;

    return Semantics(
      label: '${widget.card.title} — ${widget.card.subtitle}',
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _onTap(context);
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: isPrimary ? _PrimaryCard(card: widget.card) : _SecondaryCard(card: widget.card),
        ),
      ),
    );
  }
}

class _PrimaryCard extends StatelessWidget {
  final _MenuCard card;

  const _PrimaryCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ChabakaColors.indigoDark, ChabakaColors.indigoLight],
          begin: AlignmentDirectional.centerEnd,
          end: AlignmentDirectional.centerStart,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ChabakaColors.bordeaux.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
        child: Row(
          children: [
            Text(card.icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: ChabakaTextStyles.h3.copyWith(
                      color: ChabakaColors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.subtitle,
                    style: ChabakaTextStyles.caption.copyWith(
                      color: ChabakaColors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            // Ornement or
            Text(
              '✶',
              style: TextStyle(
                color: ChabakaColors.or.withValues(alpha: 0.8),
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryCard extends StatelessWidget {
  final _MenuCard card;

  const _SecondaryCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
        child: Row(
          children: [
            Text(card.icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: ChabakaTextStyles.label.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.subtitle,
                    style: ChabakaTextStyles.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left,
              color: scheme.outline.withValues(alpha: 0.6),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Text(
        'Chabaka v1.0',
        textAlign: TextAlign.center,
        style: ChabakaTextStyles.caption.copyWith(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
