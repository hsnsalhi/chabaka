import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── Modèle ────────────────────────────────────────────────────────────────────

class Achievement {
  final String id;
  final String title;
  final String description;
  final bool unlocked;
  final DateTime? unlockedAt;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    this.unlocked = false,
    this.unlockedAt,
  });

  Achievement copyWith({bool? unlocked, DateTime? unlockedAt}) => Achievement(
        id: id,
        title: title,
        description: description,
        unlocked: unlocked ?? this.unlocked,
        unlockedAt: unlockedAt ?? this.unlockedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'unlocked': unlocked,
        if (unlockedAt != null) 'unlockedAt': unlockedAt!.toIso8601String(),
      };
}

// ── Catalogue (12 achievements V1) ────────────────────────────────────────────

abstract final class AchievementCatalog {
  static const firstGrid = Achievement(
    id: 'first_grid',
    title: 'أول شبكة',
    description: 'أكملت شبكتك الأولى !',
  );

  static const noHint = Achievement(
    id: 'no_hint',
    title: 'بدون مساعدة',
    description: 'أكملت شبكة كاملة بدون استخدام أي تلميح.',
  );

  static const streak3 = Achievement(
    id: 'streak_3',
    title: 'ثلاثة أيام متتالية',
    description: 'لعبت 3 أيام متتالية — استمر !',
  );

  static const streak7 = Achievement(
    id: 'streak_7',
    title: 'أسبوع متواصل',
    description: 'أسبوع كامل بدون انقطاع. أنت بطل !',
  );

  static const streak30 = Achievement(
    id: 'streak_30',
    title: 'شهر بلا انقطاع',
    description: '30 يوماً متتالياً — صبر وإصرار !',
  );

  static const expert = Achievement(
    id: 'expert',
    title: 'خبير المسهمة',
    description: 'أكملت 10 شبكات — الخبرة الحقيقية.',
  );

  static const master = Achievement(
    id: 'master',
    title: 'سيّد الشبكات',
    description: 'أكملت 50 شبكة. أنت من رواد هذا الفن !',
  );

  static const legend = Achievement(
    id: 'legend',
    title: 'أسطورة المسهمة',
    description: 'أكملت 100 شبكة. شكراً لأبو سلمى !',
  );

  static const speedster = Achievement(
    id: 'speedster',
    title: 'البرق',
    description: 'أكملت شبكة في أقل من دقيقتين.',
  );

  static const perfectScore = Achievement(
    id: 'perfect_score',
    title: 'علامة كاملة',
    description: 'حصلت على أعلى درجة ممكنة — لا أخطاء ولا تلميحات وسرعة مذهلة !',
  );

  static const noErrors = Achievement(
    id: 'no_errors',
    title: 'بلا أخطاء',
    description: 'أكملت شبكة دون أي خطأ في التحقق.',
  );

  static const earlyBird = Achievement(
    id: 'early_bird',
    title: 'الصبح ربح',
    description: 'أكملت شبكة اليوم قبل الساعة 8 صباحاً.',
  );

  static const all = [
    firstGrid, noHint, streak3, streak7, streak30,
    expert, master, legend, speedster, perfectScore, noErrors, earlyBird,
  ];
}

// ── Service Hive ──────────────────────────────────────────────────────────────

class AchievementService {
  final Box _box;

  AchievementService._(this._box);

  static Future<AchievementService> open() async {
    final box = await Hive.openBox('achievements');
    return AchievementService._(box);
  }

  bool isUnlocked(String id) =>
      _box.get(id, defaultValue: false) as bool;

  Future<void> unlock(String id) async {
    await _box.put(id, true);
    await _box.put('${id}_at', DateTime.now().toIso8601String());
  }

  List<Achievement> get allWithStatus {
    return AchievementCatalog.all.map((a) {
      final unlocked = isUnlocked(a.id);
      final atRaw = _box.get('${a.id}_at') as String?;
      return a.copyWith(
        unlocked: unlocked,
        unlockedAt: atRaw != null ? DateTime.tryParse(atRaw) : null,
      );
    }).toList();
  }

  /// Vérifie et débloque les achievements applicables après une completion.
  /// Retourne la liste de ceux nouvellement débloqués.
  Future<List<Achievement>> checkAfterCompletion({
    required int totalGamesCompleted,
    required int hintsUsed,
    required int streak,
    int errorsCount = 0,
    int timeMs = 999999999,
    int score = 0,
  }) async {
    final newlyUnlocked = <Achievement>[];

    Future<void> tryUnlock(Achievement a) async {
      if (!isUnlocked(a.id)) {
        await unlock(a.id);
        newlyUnlocked.add(a.copyWith(unlocked: true, unlockedAt: DateTime.now()));
      }
    }

    if (totalGamesCompleted >= 1)   await tryUnlock(AchievementCatalog.firstGrid);
    if (hintsUsed == 0)             await tryUnlock(AchievementCatalog.noHint);
    if (errorsCount == 0)           await tryUnlock(AchievementCatalog.noErrors);
    if (streak >= 3)                await tryUnlock(AchievementCatalog.streak3);
    if (streak >= 7)                await tryUnlock(AchievementCatalog.streak7);
    if (streak >= 30)               await tryUnlock(AchievementCatalog.streak30);
    if (totalGamesCompleted >= 10)  await tryUnlock(AchievementCatalog.expert);
    if (totalGamesCompleted >= 50)  await tryUnlock(AchievementCatalog.master);
    if (totalGamesCompleted >= 100) await tryUnlock(AchievementCatalog.legend);
    if (timeMs < 120000)            await tryUnlock(AchievementCatalog.speedster);
    if (hintsUsed == 0 && errorsCount == 0 && timeMs < 300000) {
      await tryUnlock(AchievementCatalog.perfectScore);
    }

    // earlyBird : completed avant 8h00 du matin
    final now = DateTime.now();
    if (now.hour < 8) await tryUnlock(AchievementCatalog.earlyBird);

    return newlyUnlocked;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final achievementServiceProvider = Provider<AchievementService>((ref) {
  throw UnimplementedError(
    'achievementServiceProvider must be overridden via ProviderScope overrides',
  );
});

final achievementsProvider = Provider<List<Achievement>>((ref) {
  final svc = ref.watch(achievementServiceProvider);
  return svc.allWithStatus;
});
