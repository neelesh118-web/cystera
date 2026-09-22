import 'package:flutter/material.dart';

import '../../core/log/day_key.dart';
import '../../core/log/log_models.dart';
import '../../core/theme/app_theme.dart';

/// Two weeks of days, one tap to switch between them.
///
/// The strip exists because of a specific behaviour the app wants to encourage:
/// logging a day when you get round to it. Nobody opens a tracker on the worst
/// day; they open it four days later. A date picker makes that a decision, and
/// the strip makes it a tap.
///
/// Each day carries one small mark, and only one, in this order of importance:
/// a period day beats a symptom, because a period is what the prediction reads.
/// A day with nothing on it draws an empty ring rather than a grey dot — "not
/// logged" should not look like "logged as fine".
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.logs,
    required this.onSelected,
  });

  /// Oldest first, today last.
  final List<DateTime> days;

  final DateTime selected;

  /// Keyed by `DayKey.of(day)`.
  final Map<String, DayLog> logs;

  final void Function(DateTime day) onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = days[index];
          return _DayChip(
            day: day,
            log: logs[DayKey.of(day)],
            selected: DayKey.of(day) == DayKey.of(selected),
            onTap: () => onSelected(day),
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.log,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final DayLog? log;
  final bool selected;
  final VoidCallback onTap;

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mark = _mark(t);

    // Read once, into locals: a field this class does not own cannot be promoted,
    // and a label assembled from `log!` in the middle of a string is a label that
    // crashes the moment one clause is reordered.
    final entry = log;
    final symptoms = entry?.entries.length ?? 0;
    final takes = entry?.meds.length ?? 0;

    return Semantics(
      button: true,
      selected: selected,
      label: '${day.day} ${_month(day.month)}, '
          '${entry?.cycleMark != null ? 'period day, ' : ''}'
          '${entry?.nothing ?? false ? 'nothing recorded, ' : ''}'
          '${symptoms > 0 ? '$symptoms symptoms, ' : ''}'
          // The ring under the date is drawn for a day with a take on it and no
          // symptom, so the label has to say the same thing the picture does:
          // without this clause a screen reader is told "nothing recorded" about
          // a day with a tablet on it, which is the one sentence this app is not
          // allowed to get wrong.
          '${takes > 0 ? '$takes medication${takes == 1 ? '' : 's'} recorded, ' : ''}'
          '${selected ? 'selected' : 'tap to open'}',
      child: Material(
        color: selected ? t.surfaceRaised : t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                color: selected ? t.accent : t.border,
                width: selected ? 1.6 : 1.1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _weekdayLetters[day.weekday - 1],
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                mark,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The single mark under the date, in priority order.
  Widget _mark(AppTokens t) {
    final cycleMark = log?.cycleMark;
    if (cycleMark != null) {
      final period = cycleMark.kind == CycleMarkKind.period;
      return Container(
        width: period ? 12 : 8,
        height: period ? 12 : 8,
        decoration: BoxDecoration(
          color: period ? t.accent : Colors.transparent,
          border: period ? null : Border.all(color: t.accent, width: 1.6),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    final worst = log?.worst;
    if (worst != null) {
      return Container(
        width: 12,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: t.severity[worst.rampIndex],
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    if (log?.nothing ?? false) {
      // Stated, not silent. A dash between the symptom bar and the empty ring.
      return Container(
        width: 10,
        height: 2,
        color: t.textFaint,
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: t.border, width: 1.4),
      ),
    );
  }

  static String _month(int month) =>
      const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month];
}
