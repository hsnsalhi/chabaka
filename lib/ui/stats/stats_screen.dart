import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/achievements/achievement_service.dart';
import '../../data/score/score_service.dart';
import '../../data/score/streak_service.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreService = ref.watch(scoreServiceProvider);
    final quickScoreService = ref.watch(quickScoreServiceProvider);
    final streak = ref.watch(streakProvider);
    final achievements = ref.watch(achievementsProvider);

    final allScores = [
      ...scoreService.allScores(),
      ...quickScoreService.allScores(),
    ]..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    final totalCompleted = allScores.length;
    final bestTime = allScores.isEmpty
        ? null
        : allScores.map((s) => s.timeMs).reduce(math.min);
    final totalScore = allScores.fold<int>(0, (acc, s) => acc + s.score);
    final streakRecord = ref.watch(streakServiceProvider).streak;

    // 7 derniers jours
    final last7 = _buildLast7Days(allScores);

    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Cartes 2×2 ─────────────────────────────────────────────────────
          _StatsGrid(
            totalCompleted: totalCompleted,
            currentStreak: streak,
            bestStreak: streakRecord,
            bestTimeMs: bestTime,
            totalScore: totalScore,
          ),

          const SizedBox(height: 24),

          // ── Graphique 7 jours ───────────────────────────────────────────────
          _SectionTitle(title: 'نشاط آخر 7 أيام'),
          const SizedBox(height: 12),
          SizedBox(height: 140, child: _WeekChart(data: last7)),

          const SizedBox(height: 24),

          // ── Achievements ────────────────────────────────────────────────────
          _SectionTitle(title: 'الإنجازات'),
          const SizedBox(height: 12),
          _AchievementsGrid(achievements: achievements),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<int> _buildLast7Days(List<dynamic> allScores) {
    final counts = List<int>.filled(7, 0);
    final now = DateTime.now();
    for (final s in allScores) {
      final diff = now.difference(s.completedAt as DateTime).inDays;
      if (diff >= 0 && diff < 7) {
        counts[6 - diff]++;
      }
    }
    return counts;
  }
}

// ── Grille de stats ────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final int totalCompleted;
  final int currentStreak;
  final int bestStreak;
  final int? bestTimeMs;
  final int totalScore;

  const _StatsGrid({
    required this.totalCompleted,
    required this.currentStreak,
    required this.bestStreak,
    required this.bestTimeMs,
    required this.totalScore,
  });

  @override
  Widget build(BuildContext context) {
    String bestTimeStr = '--';
    if (bestTimeMs != null) {
      final m = (bestTimeMs! ~/ 60000).toString().padLeft(2, '0');
      final s = ((bestTimeMs! % 60000) ~/ 1000).toString().padLeft(2, '0');
      bestTimeStr = '$m:$s';
    }

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: [
        _StatCard(
          icon: Icons.grid_4x4,
          iconColor: ChabakaColors.bordeaux,
          value: totalCompleted.toString(),
          label: 'شبكات مكتملة',
        ),
        _StatCard(
          icon: Icons.local_fire_department,
          iconColor: const Color(0xFFEF6C00),
          value: '$currentStreak يوم',
          label: 'الإطار الحالي / الأفضل: $bestStreak',
        ),
        _StatCard(
          icon: Icons.timer_outlined,
          iconColor: ChabakaColors.or,
          value: bestTimeStr,
          label: 'أفضل وقت',
        ),
        _StatCard(
          icon: Icons.star_outlined,
          iconColor: ChabakaColors.success,
          value: totalScore.toString(),
          label: 'مجموع النقاط',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: iconColor, size: 24),
            Text(
              value,
              style: ChabakaTextStyles.h3.copyWith(
                color: scheme.onSurface,
                fontSize: 22,
              ),
              textDirection: TextDirection.rtl,
            ),
            Text(
              label,
              style: ChabakaTextStyles.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Graphique barres 7 jours ───────────────────────────────────────────────────

class _WeekChart extends StatelessWidget {
  final List<int> data; // 7 valeurs, index 0 = il y a 6 jours, 6 = aujourd'hui

  const _WeekChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxVal = data.fold<int>(1, math.max);

    final dayLabels = ['', '', '', '', '', '', ''];
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: 6 - i));
      dayLabels[i] = _shortDay(d.weekday);
    }

    return CustomPaint(
      painter: _WeekChartPainter(
        data: data,
        maxVal: maxVal,
        barColor: ChabakaColors.bordeaux,
        todayColor: ChabakaColors.or,
        labelColor: scheme.onSurface.withValues(alpha: 0.6),
        dayLabels: dayLabels,
      ),
    );
  }

  static String _shortDay(int weekday) => switch (weekday) {
    DateTime.monday => 'إث',
    DateTime.tuesday => 'ثل',
    DateTime.wednesday => 'أر',
    DateTime.thursday => 'خم',
    DateTime.friday => 'جم',
    DateTime.saturday => 'سب',
    DateTime.sunday => 'أح',
    _ => '',
  };
}

class _WeekChartPainter extends CustomPainter {
  final List<int> data;
  final int maxVal;
  final Color barColor;
  final Color todayColor;
  final Color labelColor;
  final List<String> dayLabels;

  _WeekChartPainter({
    required this.data,
    required this.maxVal,
    required this.barColor,
    required this.todayColor,
    required this.labelColor,
    required this.dayLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 20.0;
    const barSpacing = 8.0;
    final chartHeight = size.height - labelHeight - 8;
    final barWidth =
        (size.width - barSpacing * (data.length - 1)) / data.length;

    final paint = Paint();

    for (var i = 0; i < data.length; i++) {
      final x = i * (barWidth + barSpacing);
      final ratio = maxVal == 0 ? 0.0 : data[i] / maxVal;
      final barH = math.max<double>(ratio * chartHeight, 4.0);
      final y = chartHeight - barH;

      paint.color = i == data.length - 1
          ? todayColor
          : barColor.withValues(alpha: 0.75);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barWidth, barH),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );

      // Label jour
      final tp =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
              ),
            )
            ..pushStyle(ui.TextStyle(color: labelColor, fontSize: 11))
            ..addText(dayLabels[i]);
      final paragraph = tp.build();
      paragraph.layout(ui.ParagraphConstraints(width: barWidth));
      canvas.drawParagraph(paragraph, Offset(x, chartHeight + 6));
    }
  }

  @override
  bool shouldRepaint(_WeekChartPainter old) => old.data != data;
}

// ── Grille achievements ────────────────────────────────────────────────────────

class _AchievementsGrid extends StatelessWidget {
  final List<Achievement> achievements;

  const _AchievementsGrid({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: achievements.length,
      itemBuilder: (context, i) {
        return _BadgeTile(achievement: achievements[i]);
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final Achievement achievement;

  const _BadgeTile({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unlocked = achievement.unlocked;

    return Semantics(
      button: true,
      label: '${achievement.title}: ${unlocked ? "مفتوح" : "مغلق"}',
      child: GestureDetector(
        onTap: () => _showDetail(context),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: unlocked
                    ? ChabakaColors.bordeaux
                    : scheme.onSurface.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: unlocked
                      ? ChabakaColors.or
                      : scheme.onSurface.withValues(alpha: 0.15),
                  width: unlocked ? 2 : 1,
                ),
              ),
              child: Icon(
                unlocked ? Icons.emoji_events : Icons.lock_outline,
                color: unlocked
                    ? ChabakaColors.or
                    : scheme.onSurface.withValues(alpha: 0.3),
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              achievement.title,
              style: ChabakaTextStyles.caption.copyWith(
                fontSize: 10,
                color: unlocked
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.4),
                fontWeight: unlocked ? FontWeight.w600 : FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    if (!achievement.unlocked) {
      // Badge verrouillé — montrer quand même la description comme indice.
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AchievementSheet(achievement: achievement),
    );
  }
}

class _AchievementSheet extends StatelessWidget {
  final Achievement achievement;

  const _AchievementSheet({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unlocked = achievement.unlocked;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: unlocked
                    ? ChabakaColors.bordeaux
                    : scheme.onSurface.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                unlocked ? Icons.emoji_events : Icons.lock_outline,
                color: unlocked
                    ? ChabakaColors.or
                    : scheme.onSurface.withValues(alpha: 0.3),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              achievement.title,
              style: ChabakaTextStyles.h3.copyWith(color: scheme.onSurface),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            Text(
              achievement.description,
              style: ChabakaTextStyles.bodySmall.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.75),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            if (unlocked && achievement.unlockedAt != null) ...[
              const SizedBox(height: 12),
              Text(
                'فُتح في: ${_formatDate(achievement.unlockedAt!)}',
                style: ChabakaTextStyles.caption.copyWith(
                  color: ChabakaColors.success,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إغلاق'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: ChabakaTextStyles.h3.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 20,
      ),
    );
  }
}
