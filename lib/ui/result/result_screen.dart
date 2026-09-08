import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/achievements/achievement_service.dart';
import '../../data/game/game_options.dart';
import '../../data/score/streak_service.dart';
import '../../ui/game/game_screen.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

// ── Écran de résultat ──────────────────────────────────────────────────────────

class ResultScreen extends ConsumerStatefulWidget {
  final ResultArgs? args;

  const ResultScreen({super.key, this.args});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bannerCtrl;
  late final AnimationController _statsCtrl;
  late final Animation<double> _bannerScale;
  late final Animation<double> _bannerOpacity;
  late final Animation<double> _statsOpacity;
  late final Animation<Offset> _statsSlide;

  @override
  void initState() {
    super.initState();

    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _statsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _bannerScale = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _bannerCtrl, curve: Curves.elasticOut));
    _bannerOpacity = CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeIn);

    _statsOpacity = CurvedAnimation(parent: _statsCtrl, curve: Curves.easeOut);
    _statsSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _statsCtrl, curve: Curves.easeOut));

    // Séquence : banner d'abord, stats ensuite.
    _bannerCtrl.forward().then((_) {
      _statsCtrl.forward();
    });
  }

  @override
  void dispose() {
    _bannerCtrl.dispose();
    _statsCtrl.dispose();
    super.dispose();
  }

  String _formatTime(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _share(BuildContext context) {
    final args = widget.args;
    final modeLabel = args?.gameMode == GameMode.quick
        ? 'لعبة سريعة'
        : 'شبكة اليوم';
    final text = args != null
        ? 'أنهيت $modeLabel بـ ${args.score} نقطة في ${_formatTime(args.timeMs)} ! #شبكة #مسهمة'
        : 'أنهيت شبكة مسهمة ! #شبكة #مسهمة';
    // Share via clipboard en attendant le plugin share_plus (Phase C).
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم نسخ النص للمشاركة',
          style: ChabakaTextStyles.bodySmall.copyWith(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: ChabakaColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final streak = ref.watch(streakProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Banner animé
              ScaleTransition(
                scale: _bannerScale,
                child: FadeTransition(
                  opacity: _bannerOpacity,
                  child: _CongratsBanner(streak: streak),
                ),
              ),
              const SizedBox(height: 32),
              // Stats
              FadeTransition(
                opacity: _statsOpacity,
                child: SlideTransition(
                  position: _statsSlide,
                  child: Column(
                    children: [
                      if (args != null) ...[
                        _StatsCard(args: args, formatTime: _formatTime),
                        const SizedBox(height: 16),
                      ],
                      // Achievements débloqués
                      if (args != null && args.newAchievements.isNotEmpty) ...[
                        _AchievementsCard(
                          achievements: args.newAchievements
                              .cast<Achievement>()
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Streak
                      if (streak > 0) ...[
                        _StreakCard(streak: streak),
                        const SizedBox(height: 16),
                      ],
                      // Boutons
                      _ActionButtons(
                        onReplay: () {
                          final mode = widget.args?.gameMode ?? GameMode.daily;
                          if (mode == GameMode.quick) {
                            // Retour au setup pour le quick.
                            context.go(AppRoutes.quickSetup);
                          } else {
                            context.go(AppRoutes.gameDaily);
                          }
                        },
                        onShare: () => _share(context),
                        onHome: () => context.go(AppRoutes.home),
                        gameMode: widget.args?.gameMode ?? GameMode.daily,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Banner ────────────────────────────────────────────────────────────────────

class _CongratsBanner extends StatelessWidget {
  final int streak;

  const _CongratsBanner({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ChabakaColors.bordeaux, Color(0xFF9E2A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: ChabakaColors.bordeaux.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '★',
            style: TextStyle(
              fontSize: 48,
              color: ChabakaColors.or,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'أحسنت !',
            style: ChabakaTextStyles.h1.copyWith(
              color: ChabakaColors.white,
              fontSize: 44,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'أكملت شبكة اليوم بنجاح',
            style: ChabakaTextStyles.body.copyWith(
              color: ChabakaColors.white.withValues(alpha: 0.85),
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Card ─────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final ResultArgs args;
  final String Function(int ms) formatTime;

  const _StatsCard({required this.args, required this.formatTime});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Score en vedette
          _StatRow(
            icon: Icons.star,
            iconColor: ChabakaColors.or,
            label: 'النقاط',
            value: args.score.toString(),
            isHighlight: true,
          ),
          const _Divider(),
          _StatRow(
            icon: Icons.timer_outlined,
            iconColor: scheme.primary,
            label: 'الوقت',
            value: formatTime(args.timeMs),
          ),
          const _Divider(),
          _StatRow(
            icon: Icons.lightbulb_outline,
            iconColor: ChabakaColors.or,
            label: 'التلميحات',
            value: args.hintsUsed.toString(),
          ),
          const _Divider(),
          _StatRow(
            icon: Icons.warning_amber_outlined,
            iconColor: ChabakaColors.error,
            label: 'الأخطاء',
            value: args.errorsCount.toString(),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 1,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isHighlight;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: '$label: $value',
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: ChabakaTextStyles.label.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: ChabakaTextStyles.label.copyWith(
              color: isHighlight ? ChabakaColors.bordeaux : scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: isHighlight ? 22 : 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Achievements Card ─────────────────────────────────────────────────────────

class _AchievementsCard extends StatelessWidget {
  final List<Achievement> achievements;

  const _AchievementsCard({required this.achievements});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ChabakaColors.or.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChabakaColors.or.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '★',
                style: TextStyle(color: ChabakaColors.or, fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'إنجازات جديدة !',
                style: ChabakaTextStyles.label.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final a in achievements) ...[
            _AchievementRow(achievement: a),
            if (a != achievements.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  final Achievement achievement;

  const _AchievementRow({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'إنجاز: ${achievement.title} — ${achievement.description}',
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ChabakaColors.or.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🏆', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: ChabakaTextStyles.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  achievement.description,
                  style: ChabakaTextStyles.caption.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Streak Card ───────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final int streak;

  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Semantics(
        label: 'السلسلة الحالية: $streak يوم متتالي',
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سلسلتك الحالية',
                    style: ChabakaTextStyles.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '$streak ${streak == 1 ? "يوم" : "أيام متتالية"}',
                    style: ChabakaTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ChabakaColors.bordeaux,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Boutons d'action ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final VoidCallback onReplay;
  final VoidCallback onShare;
  final VoidCallback onHome;
  final GameMode gameMode;

  const _ActionButtons({
    required this.onReplay,
    required this.onShare,
    required this.onHome,
    required this.gameMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Rejouer / Nouvelle partie
        Semantics(
          button: true,
          label: gameMode == GameMode.quick ? 'لعبة جديدة' : 'إعادة اللعب',
          child: ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              onReplay();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ChabakaColors.bordeaux,
              foregroundColor: ChabakaColors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: Text(
              gameMode == GameMode.quick ? 'لعبة جديدة' : 'إعادة اللعب',
              style: ChabakaTextStyles.labelLarge.copyWith(
                color: ChabakaColors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Partager
        Semantics(
          button: true,
          label: 'مشاركة النتيجة',
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              onShare();
            },
            icon: const Icon(Icons.share_outlined, size: 20),
            label: Text(
              'مشاركة',
              style: ChabakaTextStyles.label.copyWith(
                color: ChabakaColors.bordeaux,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ChabakaColors.bordeaux,
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: ChabakaColors.bordeaux, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Accueil
        Semantics(
          button: true,
          label: 'العودة للرئيسية',
          child: TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              onHome();
            },
            child: Text(
              'الرئيسية',
              style: ChabakaTextStyles.label.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
