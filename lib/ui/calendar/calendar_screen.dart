import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/score/score_service.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/text_styles.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  }

  void _prevMonth() => setState(
        () => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1),
      );

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    if (!next.isAfter(DateTime(now.year, now.month))) {
      setState(() => _displayedMonth = next);
    }
  }

  bool _isCurrentMonth() {
    final now = DateTime.now();
    return _displayedMonth.year == now.year && _displayedMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final scoreService = ref.watch(scoreServiceProvider);
    final allScores = scoreService.allScores();

    // Construire une map date → score pour coloration
    final completedDays = <String, int>{};
    for (final s in allScores) {
      final key = _dateKey(s.completedAt);
      completedDays[key] = (completedDays[key] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقويم'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: Column(
        children: [
          // ── Navigation mois ──────────────────────────────────────────────────
          _MonthHeader(
            displayedMonth: _displayedMonth,
            onPrev: _prevMonth,
            onNext: _isCurrentMonth() ? null : _nextMonth,
          ),

          // ── En-têtes jours ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _DayHeaders(),
          ),

          // ── Grille du mois ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _MonthGrid(
                month: _displayedMonth,
                completedDays: completedDays,
                onDayTap: _onDayTap,
              ),
            ),
          ),

          // ── Légende ─────────────────────────────────────────────────────────
          _Legend(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _onDayTap(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tapped = DateTime(day.year, day.month, day.day);

    if (tapped.isAfter(today)) return; // futur — ignoré

    // Naviguer vers le jeu quotidien (mode daily utilise la date du jour)
    context.go(AppRoutes.gameDaily);
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ── En-tête mois ─────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime displayedMonth;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _MonthHeader({
    required this.displayedMonth,
    required this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monthName = _arabicMonth(displayedMonth.month);
    final label = '$monthName ${displayedMonth.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Bouton suivant (en RTL, la flèche droite = suivant = à gauche visuellement)
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            tooltip: 'الشهر التالي',
            color: onNext != null
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
          Text(
            label,
            style: ChabakaTextStyles.h3.copyWith(
              color: scheme.onSurface,
              fontSize: 20,
            ),
          ),
          // Bouton précédent (flèche gauche = précédent = à droite en RTL)
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            tooltip: 'الشهر السابق',
            color: scheme.onSurface,
          ),
        ],
      ),
    );
  }

  static String _arabicMonth(int m) => const [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'ماي', 'يونيو',
        'يوليوز', 'غشت', 'شتنبر', 'أكتوبر', 'نونبر', 'دجنبر',
      ][m - 1];
}

// ── En-têtes jours ────────────────────────────────────────────────────────────

class _DayHeaders extends StatelessWidget {
  // En arabe RTL : on commence par السبت (samedi) ou الأحد.
  // On utilise la convention française : lundi en premier (colonne 0).
  static const _headers = ['إث', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // En RTL la GridView inversera l'ordre visuellement — on les laisse dans
    // l'ordre logique et on laisse Directionality gérer.
    return Row(
      children: _headers.map((h) {
        return Expanded(
          child: Center(
            child: Text(
              h,
              style: ChabakaTextStyles.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Grille mois ───────────────────────────────────────────────────────────────

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, int> completedDays;
  final ValueChanged<DateTime> onDayTap;

  const _MonthGrid({
    required this.month,
    required this.completedDays,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    // Calcul des cases vides avant le 1er du mois.
    final firstDay = DateTime(month.year, month.month, 1);
    // weekday : 1=lundi…7=dimanche. On veut lundi=0.
    final leadingEmpty = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final totalCells = leadingEmpty + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: rows * 7,
      itemBuilder: (context, index) {
        final dayNum = index - leadingEmpty + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          return const SizedBox.shrink();
        }
        final date = DateTime(month.year, month.month, dayNum);
        final key = _dateKey(date);
        final count = completedDays[key] ?? 0;
        final isFuture = date.isAfter(today);
        final isToday = date == today;

        return _DayCell(
          day: dayNum,
          completionCount: count,
          isFuture: isFuture,
          isToday: isToday,
          onTap: isFuture ? null : () => onDayTap(date),
        );
      },
    );
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ── Cellule jour ──────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int day;
  final int completionCount;
  final bool isFuture;
  final bool isToday;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.completionCount,
    required this.isFuture,
    required this.isToday,
    this.onTap,
  });

  Color _bgColor() {
    if (isFuture) return Colors.transparent;
    if (completionCount >= 2) return ChabakaColors.success; // vert = complété
    if (completionCount == 1) return const Color(0xFFFBBF24); // jaune = partiel
    return Colors.transparent; // gris = pas joué
  }

  Color _borderColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isToday) return ChabakaColors.bordeaux;
    if (isFuture) return Colors.transparent;
    if (completionCount == 0) return scheme.outlineVariant;
    return Colors.transparent;
  }

  Color _textColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isFuture) return scheme.onSurface.withValues(alpha: 0.2);
    if (completionCount >= 1) return Colors.white;
    return scheme.onSurface.withValues(alpha: 0.7);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'يوم $day${completionCount > 0 ? "، مكتمل" : ""}',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _bgColor(),
            shape: BoxShape.circle,
            border: Border.all(
              color: _borderColor(context),
              width: isToday ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              day.toString(),
              style: ChabakaTextStyles.caption.copyWith(
                color: _textColor(context),
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                fontSize: 13,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Légende ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LegendItem(color: ChabakaColors.success, label: 'مكتمل'),
          const SizedBox(width: 16),
          _LegendItem(color: const Color(0xFFFBBF24), label: 'جزئي'),
          const SizedBox(width: 16),
          _LegendItem(
            color: scheme.outlineVariant,
            label: 'لم يُلعب',
            outlined: true,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool outlined;

  const _LegendItem({required this.color, required this.label, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: outlined ? Colors.transparent : color,
            border: outlined ? Border.all(color: color, width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: ChabakaTextStyles.caption.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
