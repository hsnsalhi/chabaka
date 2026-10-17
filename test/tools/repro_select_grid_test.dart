/// Reproduction : ouvrir une partie rapide avec la vraie KB puis sélectionner
/// une case. Outil de diagnostic (tag tool), exclu de la CI.
@Tags(['tool'])
library;

import 'dart:io';

import 'package:chabaka/data/game/game_options.dart';
import 'package:chabaka/data/persistence/settings_service.dart';
import 'package:chabaka/data/score/score_service.dart';
import 'package:chabaka/data/score/streak_service.dart';
import 'package:chabaka/core/achievements/achievement_service.dart';
import 'package:chabaka/puzzle/kb/kb_repository_sqflite.dart';
import 'package:chabaka/ui/game/game_screen.dart';
import 'package:chabaka/ui/grid/cell_widgets.dart';
import 'package:chabaka/ui/grid/puzzle_providers.dart';
import 'package:chabaka/ui/theme/chabaka_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _diff = String.fromEnvironment('DIFF', defaultValue: 'beginner');
const _palette = String.fromEnvironment('PALETTE', defaultValue: 'classic');
const _mode = String.fromEnvironment('MODE', defaultValue: 'quick');
const _theme = String.fromEnvironment('THEME', defaultValue: 'light');

void main() {
  late Directory tmp;
  setUpAll(() async {
    sqfliteFfiInit();
    tmp = Directory.systemTemp.createTempSync('chabaka_repro');
    Hive.init(tmp.path);
  });

  testWidgets(
    'partie rapide $_diff : ouverture puis sélection d\'une case',
    (tester) async {
      final errors = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (!m.contains('overflowed')) errors.add(m);
      };

      late ProviderContainer container;
      await tester.runAsync(() async {
        final settings = await SettingsService.open();
        await settings.setPalette(ChabakaPalette.fromName(_palette));
        final overrides = [
          settingsServiceProvider.overrideWithValue(settings),
          scoreServiceProvider.overrideWithValue(await ScoreService.open()),
          quickScoreServiceProvider.overrideWithValue(
            await QuickScoreService.open(),
          ),
          streakServiceProvider.overrideWithValue(await StreakService.open()),
          achievementServiceProvider.overrideWithValue(
            await AchievementService.open(),
          ),
          kbRepositoryProvider.overrideWith(
            (ref) => openKbRepositoryFromFile(
              '${Directory.current.path}/assets/kb/chabaka_kb.sqlite',
              databaseFactoryOverride: databaseFactoryFfi,
            ),
          ),
        ];
        container = ProviderContainer(overrides: overrides);
      });

      final palette = ChabakaPalette.fromName(_palette);
      // Écran d'iPhone (390×844 points).
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: switch (_theme) {
              'dark' => ChabakaTheme.dark(palette),
              'sepia' => ChabakaTheme.sepia(palette),
              _ => ChabakaTheme.light(palette),
            },
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: GameScreen(
                options: _mode == 'daily'
                    ? GameOptions.daily()
                    : GameOptions.quick(
                        difficulty: Difficulty.values.byName(_diff),
                      ),
              ),
            ),
          ),
        ),
      );

      // Laisser la génération (vraie IO + CPU) se faire.
      for (var i = 0; i < 240; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (container.read(puzzleProvider).hasValue ||
            container.read(puzzleProvider).hasError) {
          break;
        }
      }
      final st = container.read(puzzleProvider);
      // ignore: avoid_print
      print('état puzzle : value=${st.hasValue} error=${st.error}');
      expect(st.hasValue, isTrue, reason: 'grille non chargée : ${st.error}');
      await tester.pump(const Duration(milliseconds: 300));

      final cells = find.byType(LetterCellWidget);
      // ignore: avoid_print
      print('cases lettre affichées : ${cells.evaluate().length}');
      await tester.tap(cells.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(cells.at(3));
      await tester.pump(const Duration(milliseconds: 300));
      // Saisie d'une lettre
      await tester.enterText(cells.at(3), 'ب');
      await tester.pump(const Duration(milliseconds: 300));

      final exc = tester.takeException();
      // ignore: avoid_print
      print('exception : $exc');
      // ignore: avoid_print
      print('erreurs Flutter : ${errors.length}');
      for (final e in errors.take(5)) {
        // ignore: avoid_print
        print('--- $e');
      }
      container.read(timerProvider.notifier).stop();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      FlutterError.onError = prev;
      expect(exc, isNull);
      expect(errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
