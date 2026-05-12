import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _boxName = 'settings';
const _keyStreak = 'streak';
const _keyLastCompletion = 'last_completion_date';

// ── Service ───────────────────────────────────────────────────────────────────

class StreakService {
  final Box _box;

  StreakService._(this._box);

  /// Réutilise la box 'settings' déjà ouverte par SettingsService.
  static Future<StreakService> open() async {
    final box = await Hive.openBox(_boxName);
    return StreakService._(box);
  }

  int get streak => _box.get(_keyStreak, defaultValue: 0) as int;

  String? get lastCompletionDate =>
      _box.get(_keyLastCompletion) as String?;

  /// Appeler après chaque completion réussie.
  /// Retourne le nouveau streak.
  Future<int> recordCompletion() async {
    final today = _todayIso();
    final last = lastCompletionDate;

    if (last == today) {
      // Déjà complété aujourd'hui → streak inchangé.
      return streak;
    }

    final newStreak = _isYesterday(last) ? streak + 1 : 1;
    await _box.put(_keyStreak, newStreak);
    await _box.put(_keyLastCompletion, today);
    return newStreak;
  }

  /// Vérification passive : si plus d'1 jour passé sans completion, reset.
  /// À appeler au démarrage de l'app.
  Future<void> maybeReset() async {
    final last = lastCompletionDate;
    if (last == null) return;
    if (!_isYesterday(last) && last != _todayIso()) {
      await _box.put(_keyStreak, 0);
    }
  }

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static bool _isYesterday(String? dateIso) {
    if (dateIso == null) return false;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yIso =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    return dateIso == yIso;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final streakServiceProvider = Provider<StreakService>((ref) {
  throw UnimplementedError(
    'streakServiceProvider must be overridden via ProviderScope overrides',
  );
});

class StreakNotifier extends Notifier<int> {
  @override
  int build() {
    final svc = ref.watch(streakServiceProvider);
    return svc.streak;
  }

  Future<int> recordCompletion() async {
    final svc = ref.read(streakServiceProvider);
    final newStreak = await svc.recordCompletion();
    state = newStreak;
    return newStreak;
  }

  /// Force la valeur du streak (après sync externe, ex. depuis GameScreen).
  void setStreak(int value) => state = value;
}

final streakProvider = NotifierProvider<StreakNotifier, int>(StreakNotifier.new);
