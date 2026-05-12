import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/persistence/settings_service.dart';

/// Service haptique centralisé.
/// Toutes les méthodes sont no-op si hapticEnabled == false.
class HapticsService {
  final SettingsService _settings;

  HapticsService(this._settings);

  Future<void> lightTap() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.lightImpact();
  }

  Future<void> mediumTap() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.mediumImpact();
  }

  Future<void> successHaptic() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  Future<void> errorHaptic() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.heavyImpact();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final hapticsServiceProvider = Provider<HapticsService>((ref) {
  final settings = ref.watch(settingsServiceProvider);
  return HapticsService(settings);
});
