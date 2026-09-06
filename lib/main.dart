import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/router.dart';
import 'core/achievements/achievement_service.dart';
import 'data/persistence/settings_service.dart';
import 'data/score/score_service.dart' show ScoreService, QuickScoreService, scoreServiceProvider, quickScoreServiceProvider;
import 'data/score/streak_service.dart';
import 'ui/theme/chabaka_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Grille de mots fléchés : portrait uniquement (cf. Info.plist / Manifest).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Hive.initFlutter();

  // Ouvre la box settings avant le lancement pour que le provider soit dispo.
  final settingsSvc = await SettingsService.open();

  // Phase B — score, streak, achievements.
  final scoreSvc = await ScoreService.open();
  final quickScoreSvc = await QuickScoreService.open();
  final streakSvc = await StreakService.open();
  await streakSvc.maybeReset(); // reset silencieux si >1 jour sans jeu
  final achievementSvc = await AchievementService.open();

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsSvc),
        scoreServiceProvider.overrideWithValue(scoreSvc),
        quickScoreServiceProvider.overrideWithValue(quickScoreSvc),
        streakServiceProvider.overrideWithValue(streakSvc),
        achievementServiceProvider.overrideWithValue(achievementSvc),
      ],
      child: const ChabakaApp(),
    ),
  );
}

class ChabakaApp extends ConsumerWidget {
  const ChabakaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'شبكة',
      debugShowCheckedModeBanner: false,
      // ── Thèmes ──────────────────────────────────────────────────────────────
      theme: ChabakaTheme.light(),
      darkTheme: ChabakaTheme.dark(),
      // Le mode sépia est appliqué comme override light avec ColorScheme custom.
      // On map ChabakaThemeMode → ThemeMode ici.
      themeMode: switch (themeMode) {
        ChabakaThemeMode.dark => ThemeMode.dark,
        _ => ThemeMode.light,
      },
      // ── Router ──────────────────────────────────────────────────────────────
      routerConfig: router,
      // ── RTL + sépia ─────────────────────────────────────────────────────────
      builder: (context, child) {
        // Sépia : on surcharge le theme directement ici
        final effectiveTheme = themeMode == ChabakaThemeMode.sepia
            ? ChabakaTheme.sepia()
            : Theme.of(context);

        return Theme(
          data: effectiveTheme,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
