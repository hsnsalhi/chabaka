import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../ui/theme/chabaka_theme.dart';

const _boxName = 'settings';
const _keyOnboarding = 'onboarding_done';
const _keyTheme = 'theme_mode';
const _keySound = 'sound_enabled';
const _keyHaptic = 'haptic_enabled';

/// Service de persistance des réglages utilisateur via Hive.
/// Doit être initialisé après [Hive.initFlutter()].
class SettingsService {
  final Box _box;

  SettingsService._(this._box);

  static Future<SettingsService> open() async {
    final box = await Hive.openBox(_boxName);
    return SettingsService._(box);
  }

  // ── Onboarding ──────────────────────────────────────────────────────────────

  bool get onboardingDone =>
      _box.get(_keyOnboarding, defaultValue: false) as bool;
  Future<void> setOnboardingDone(bool v) => _box.put(_keyOnboarding, v);

  // ── Theme ───────────────────────────────────────────────────────────────────

  ChabakaThemeMode get themeMode {
    final raw = _box.get(_keyTheme, defaultValue: 'light') as String;
    return switch (raw) {
      'dark' => ChabakaThemeMode.dark,
      'sepia' => ChabakaThemeMode.sepia,
      _ => ChabakaThemeMode.light,
    };
  }

  Future<void> setThemeMode(ChabakaThemeMode mode) =>
      _box.put(_keyTheme, mode.name);

  // ── Son ─────────────────────────────────────────────────────────────────────

  bool get soundEnabled => _box.get(_keySound, defaultValue: true) as bool;
  Future<void> setSoundEnabled(bool v) => _box.put(_keySound, v);

  // ── Haptique ────────────────────────────────────────────────────────────────

  bool get hapticEnabled => _box.get(_keyHaptic, defaultValue: true) as bool;
  Future<void> setHapticEnabled(bool v) => _box.put(_keyHaptic, v);
}

// ── Riverpod providers ─────────────────────────────────────────────────────────

final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError(
    'settingsServiceProvider must be overridden via ProviderScope overrides',
  );
});

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ChabakaThemeMode>((ref) {
      final svc = ref.watch(settingsServiceProvider);
      return ThemeModeNotifier(svc);
    });

class ThemeModeNotifier extends StateNotifier<ChabakaThemeMode> {
  final SettingsService _svc;

  ThemeModeNotifier(this._svc) : super(_svc.themeMode);

  Future<void> set(ChabakaThemeMode mode) async {
    await _svc.setThemeMode(mode);
    state = mode;
  }
}

final onboardingDoneProvider = StateNotifierProvider<OnboardingNotifier, bool>((
  ref,
) {
  final svc = ref.watch(settingsServiceProvider);
  return OnboardingNotifier(svc);
});

class OnboardingNotifier extends StateNotifier<bool> {
  final SettingsService _svc;

  OnboardingNotifier(this._svc) : super(_svc.onboardingDone);

  Future<void> markDone() async {
    await _svc.setOnboardingDone(true);
    state = true;
  }
}
