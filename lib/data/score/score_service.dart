import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── Modèle d'un score de partie ────────────────────────────────────────────────

class GameScore {
  final String gridId;
  final int score;
  final int timeMs;
  final int hintsUsed;
  final int errorsCount;
  final DateTime completedAt;

  const GameScore({
    required this.gridId,
    required this.score,
    required this.timeMs,
    required this.hintsUsed,
    required this.errorsCount,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'gridId': gridId,
    'score': score,
    'timeMs': timeMs,
    'hintsUsed': hintsUsed,
    'errorsCount': errorsCount,
    'completedAt': completedAt.toIso8601String(),
  };

  factory GameScore.fromJson(Map<String, dynamic> json) => GameScore(
    gridId: json['gridId'] as String,
    score: json['score'] as int,
    timeMs: json['timeMs'] as int,
    hintsUsed: json['hintsUsed'] as int,
    errorsCount: json['errorsCount'] as int,
    completedAt: DateTime.parse(json['completedAt'] as String),
  );
}

// ── Calcul du score ─────────────────────────────────────────────────────────────

class ScoreCalculator {
  static const _base = 1000;
  static const _bonusNoHint = 300;
  static const _penaltyPerHint = 50;
  static const _penaltyPerError = 20;
  static const _rapidityThresholdMs = 5 * 60 * 1000; // 5 min

  /// Score final après completion.
  /// - Base : 1000
  /// - Bonus rapidité : -1 pt/seconde au-delà de 5 min (max 0)
  /// - Bonus sans indice : +300 si hintsUsed == 0
  /// - Pénalités : -50 par hint, -20 par erreur validée
  /// - [multiplier] : multiplicateur selon la difficulté (1.0 à 3.0)
  static int calculate({
    required int timeMs,
    required int hintsUsed,
    required int errorsCount,
    double multiplier = 1.0,
  }) {
    int score = _base;

    // Bonus/malus rapidité
    final overtime = timeMs - _rapidityThresholdMs;
    if (overtime > 0) {
      score -= (overtime / 1000).floor(); // -1 pt/sec
    }

    // Bonus no-hint
    if (hintsUsed == 0) score += _bonusNoHint;

    // Pénalités
    score -= hintsUsed * _penaltyPerHint;
    score -= errorsCount * _penaltyPerError;

    final base = score.clamp(0, _base + _bonusNoHint);
    return (base * multiplier).round();
  }
}

// ── Service Hive ─────────────────────────────────────────────────────────────────

class ScoreService {
  final Box _box;

  ScoreService._(this._box);

  static Future<ScoreService> open() async {
    final box = await Hive.openBox('scores');
    return ScoreService._(box);
  }

  Future<void> saveScore(GameScore score) async {
    await _box.put(score.gridId, score.toJson());
  }

  GameScore? getScore(String gridId) {
    final raw = _box.get(gridId);
    if (raw == null) return null;
    return GameScore.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  List<GameScore> allScores() {
    return _box.values
        .map((v) => GameScore.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  int get totalGamesPlayed => _box.length;
}

// ── Service Hive scores Quick ─────────────────────────────────────────────────────

/// Persiste les scores du mode rapide dans une box dédiée.
/// Clé : {difficulty}_{themes}_{epochSec}
class QuickScoreService {
  final Box _box;

  QuickScoreService._(this._box);

  static Future<QuickScoreService> open() async {
    final box = await Hive.openBox('scores_quick');
    return QuickScoreService._(box);
  }

  Future<void> saveScore(GameScore score, String hiveKey) async {
    final epochSec = score.completedAt.millisecondsSinceEpoch ~/ 1000;
    final key = '${hiveKey}_$epochSec';
    await _box.put(key, score.toJson());
  }

  List<GameScore> allScores() {
    return _box.values
        .map((v) => GameScore.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  int get totalGamesPlayed => _box.length;
}

// ── Providers Riverpod ──────────────────────────────────────────────────────────

final scoreServiceProvider = Provider<ScoreService>((ref) {
  throw UnimplementedError(
    'scoreServiceProvider must be overridden via ProviderScope overrides',
  );
});

final quickScoreServiceProvider = Provider<QuickScoreService>((ref) {
  throw UnimplementedError(
    'quickScoreServiceProvider must be overridden via ProviderScope overrides',
  );
});

// ── Timer state ─────────────────────────────────────────────────────────────────

class TimerState {
  final Duration elapsed;
  final bool running;

  const TimerState({required this.elapsed, required this.running});

  TimerState copyWith({Duration? elapsed, bool? running}) => TimerState(
    elapsed: elapsed ?? this.elapsed,
    running: running ?? this.running,
  );

  String get formatted {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class TimerNotifier extends Notifier<TimerState> {
  static const _tick = Duration(seconds: 1);

  @override
  TimerState build() =>
      const TimerState(elapsed: Duration.zero, running: false);

  void start() {
    if (state.running) return;
    state = state.copyWith(running: true);
    _scheduleNext();
  }

  void stop() {
    state = state.copyWith(running: false);
  }

  void reset() {
    state = const TimerState(elapsed: Duration.zero, running: false);
  }

  void _scheduleNext() {
    Future.delayed(_tick, () {
      if (!state.running) return;
      state = state.copyWith(elapsed: state.elapsed + _tick);
      _scheduleNext();
    });
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);

// ── Score courant de la partie ──────────────────────────────────────────────────

class CurrentScoreNotifier extends Notifier<int> {
  @override
  int build() => ScoreCalculator._base;

  void applyHint() {
    state = (state - ScoreCalculator._penaltyPerHint).clamp(0, state);
  }

  void applyError() {
    state = (state - ScoreCalculator._penaltyPerError).clamp(0, state);
  }

  void applyTimeBonus(Duration elapsed) {
    final overtime =
        elapsed.inMilliseconds - ScoreCalculator._rapidityThresholdMs;
    if (overtime > 0) {
      state = (state - (overtime / 1000).floor()).clamp(0, state);
    }
  }

  /// Calcule le score final consolidé.
  int finalScore({
    required int hintsUsed,
    required int errorsCount,
    required int timeMs,
  }) {
    return ScoreCalculator.calculate(
      timeMs: timeMs,
      hintsUsed: hintsUsed,
      errorsCount: errorsCount,
    );
  }

  void reset() {
    state = ScoreCalculator._base;
  }
}

final currentScoreProvider = NotifierProvider<CurrentScoreNotifier, int>(
  CurrentScoreNotifier.new,
);
