import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/persistence/settings_service.dart';
import '../../ui/common/arabesque_background.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();

    // Attendre 1.5s avant de naviguer (laisse le temps au fond/animation
    // ET au chargement KB s'il est rapide).
    Future.delayed(const Duration(milliseconds: 1500), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    final onboardingDone = ref.read(settingsServiceProvider).onboardingDone;
    context.go(onboardingDone ? AppRoutes.home : AppRoutes.onboarding);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChabakaColors.bordeaux,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Arabesques en transparence sur fond bordeaux
          const ArabesqueBackground(color: ChabakaColors.white, opacity: 0.05),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: const _LogoCalligraphique(),
                  ),
                ),
                const Spacer(flex: 2),
                FadeTransition(opacity: _fade, child: const _Subtitle()),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logo ─────────────────────────────────────────────────────────────────────

class _LogoCalligraphique extends StatelessWidget {
  const _LogoCalligraphique();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _OrnementDivider(),
        const SizedBox(height: 16),
        Semantics(
          label: 'شبكة — تطبيق الكلمات المسهمة العربية',
          child: ExcludeSemantics(
            child: Text(
              'شبكة',
              textDirection: TextDirection.rtl,
              style: ChabakaTextStyles.h1.copyWith(
                color: ChabakaColors.or,
                fontSize: 72,
                height: 1.1,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _OrnementDivider(),
      ],
    );
  }
}

class _OrnementDivider extends StatelessWidget {
  const _OrnementDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _line(),
        const SizedBox(width: 12),
        const Text(
          '✶', // étoile géométrique 6 branches
          style: TextStyle(color: ChabakaColors.or, fontSize: 14),
        ),
        const SizedBox(width: 12),
        _line(),
      ],
    );
  }

  Widget _line() => Container(
    width: 48,
    height: 1,
    color: Color.fromRGBO(
      (ChabakaColors.or.r * 255).round(),
      (ChabakaColors.or.g * 255).round(),
      (ChabakaColors.or.b * 255).round(),
      0.5,
    ),
  );
}

// ── Subtitle ─────────────────────────────────────────────────────────────────

class _Subtitle extends StatelessWidget {
  const _Subtitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CHABAKA',
          style: ChabakaTextStyles.splashSubtitle.copyWith(
            letterSpacing: 4,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'كلمات مسهمة عربية',
          style: ChabakaTextStyles.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
