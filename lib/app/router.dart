import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/game/game_options.dart';
import '../ui/splash/splash_screen.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/game/game_screen.dart' show GameScreen, ResultArgs;
import '../ui/quick_setup/quick_setup_screen.dart';
import '../ui/result/result_screen.dart';

import '../ui/settings/settings_screen.dart';
import '../ui/stats/stats_screen.dart';
import '../ui/calendar/calendar_screen.dart';

/// Routes nommées de l'application.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const home = '/home';

  // Jeu — deux variantes
  static const gameDaily = '/game/daily';
  static const gameQuick = '/game/quick';

  // Setup mode rapide
  static const quickSetup = '/quick-setup';

  static const result = '/result';
  static const stats = '/stats';
  static const settings = '/settings';
  static const calendar = '/calendar';

  // Rétro-compat Phase A — redirige vers /game/daily
  static const game = '/game';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      // Route legacy /game → redirige vers /game/daily
      GoRoute(
        path: AppRoutes.game,
        redirect: (context, state) => AppRoutes.gameDaily,
      ),
      // Jeu quotidien — options fixées (daily + intermediate + tous thèmes)
      GoRoute(
        path: AppRoutes.gameDaily,
        builder: (context, state) => GameScreen(options: GameOptions.daily()),
      ),
      // Écran de configuration mode rapide
      GoRoute(
        path: AppRoutes.quickSetup,
        builder: (context, state) => const QuickSetupScreen(),
      ),
      // Jeu rapide — options passées via extra
      GoRoute(
        path: AppRoutes.gameQuick,
        builder: (context, state) {
          final opts = state.extra as GameOptions?;
          return GameScreen(
            options:
                opts ?? GameOptions.quick(difficulty: Difficulty.intermediate),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.result,
        builder: (context, state) {
          final args = state.extra as ResultArgs?;
          return ResultScreen(args: args);
        },
      ),
      GoRoute(
        path: AppRoutes.stats,
        builder: (context, state) => const StatsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, state) => const CalendarScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'الصفحة غير موجودة',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    ),
  );
});
