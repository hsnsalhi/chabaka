import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/persistence/settings_service.dart';

/// Service audio centralisé.
/// Initialise audioplayers et expose des méthodes sémantiques.
/// En mode silencieux ou si les assets sont absents, les appels sont no-op.
class AudioService {
  final SettingsService _settings;

  // Un player par canal pour éviter la coupure des sons qui se chevauchent.
  final AudioPlayer _clickPlayer = AudioPlayer();
  final AudioPlayer _letterPlayer = AudioPlayer();
  final AudioPlayer _completePlayer = AudioPlayer();
  final AudioPlayer _unlockPlayer = AudioPlayer();

  AudioService(this._settings);

  Future<void> _play(AudioPlayer player, String assetPath) async {
    if (!_settings.soundEnabled) return;
    try {
      await player.play(AssetSource(assetPath));
    } catch (_) {
      // Asset absent ou erreur device — silencieux.
    }
  }

  /// Son au tap sur une cellule.
  Future<void> playClick() => _play(_clickPlayer, 'sounds/click.mp3');

  /// Son à l'entrée d'une lettre.
  Future<void> playLetter() => _play(_letterPlayer, 'sounds/letter.mp3');

  /// Son de completion de grille.
  Future<void> playComplete() => _play(_completePlayer, 'sounds/complete.mp3');

  /// Son de déblocage d'un achievement.
  Future<void> playUnlock() => _play(_unlockPlayer, 'sounds/unlock.mp3');

  void dispose() {
    _clickPlayer.dispose();
    _letterPlayer.dispose();
    _completePlayer.dispose();
    _unlockPlayer.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final audioServiceProvider = Provider<AudioService>((ref) {
  final settings = ref.watch(settingsServiceProvider);
  final svc = AudioService(settings);
  ref.onDispose(svc.dispose);
  return svc;
});
