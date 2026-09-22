import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/cycle/cycle_forecast.dart';
import '../../core/i18n/app_text.dart';
import '../../core/log/log_controller.dart';
import '../../core/log/log_models.dart';
import '../../core/log/severity.dart';
import '../../core/log/symptom_catalogue.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import '../../core/widgets/page_hero.dart';
import '../../core/widgets/page_scaffold.dart';
import '../log/undo_toast.dart';

/// The screen the app opens on, and the only thing it should ever ask for: one
/// tap.
///
/// Every line here is read from the record. There is no invented cycle day, no
/// placeholder chart, and no summary of data that was never entered — the header
/// says "Nothing recorded yet" when that is true, which is the single most
/// important sentence on the screen for someone opening the app for the first
/// time.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<LogController>();
    final today = log.todayLog;

    return PageScaffold(
      // The app's name is the mark beside this line rather than a word above it: a
      // header that says "Cystera" on every screen is a line read once and never
      // again, and the date is the part that changes. The headline below is the
      // app's one honest sentence about the day.
      header: PageHero(
        overline: DateFormat('EEEE, d MMMM').format(log.today),
        title: HeroTitle(_headline(context, log, today)),
        subtitle: _subtitle(log, today),
      ),
      children: [
        if (log.error case final error?) _Problem(text: error),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.go('/log'),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Log how I feel'),
              ),
            ),
          ],
        ),
        if (!today.nothing && today.entries.isEmpty)
          OutlinedButton(
            onPressed: log.canWrite
                ? () => writeAndOfferUndo(context, log, () => log.setNothing(true))
                : null,
            child: Text(AppTextScope.of(context).nothingToday),
          ),
        if (today.cycleMark case final mark?) _CycleLine(mark: mark),
        if (today.entries.isNotEmpty) _LoggedToday(entries: today.entries),
        if (today.note case final note?) _Note(text: note),
        _CycleCard(
          position: log.position,
          forecast: log.forecast,
          loading: log.loading,
          // The controller's today, not the machine's: the summary and the card
          // it links to have to agree about what day it is, including in a test.
          today: log.today,
        ),
        _TrustNote(onTap: () => context.go('/settings')),
      ],
    );
  }

  /// The header's one line, and it never guesses.
  static String _headline(BuildContext context, LogController log, DayLog today) {
    if (log.loading && today.isEmpty && !today.nothing) return 'Reading your record…';
    if (today.nothing) return AppTextScope.of(context).nothingToday;
    if (today.entries.isEmpty) return 'Nothing recorded yet';
    final count = today.entries.length;
    return count == 1 ? '1 symptom logged' : '$count symptoms logged';
  }

  static String _subtitle(LogController log, DayLog today) {
    if (today.nothing) return 'A day with nothing to report, which is worth recording.';
    if (today.entries.isEmpty) {
      return 'Nothing is recorded for today. That is the honest state, not an empty chart.';
    }
    final count = today.entries.length;
    final worst = today.worst;
    return '${count == 1 ? 'One thing' : '$count things'} logged today'
        '${worst == null ? '' : ', the worst of it ${worst.word.toLowerCase()}'}';
  }
}

class _LoggedToday extends StatelessWidget {
  const _LoggedToday({required this.entries});

  final Map<String, Severity> entries;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ordered = entries.entries.toList()
      ..sort((a, b) => b.value.level.compareTo(a.value.level));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today so far', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final entry in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.severity[entry.value.rampIndex],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Symptom.byId(entry.key)?.label ?? entry.key,
                      style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    entry.value.word,
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CycleLine extends StatelessWidget {
  const _CycleLine({required this.mark});

  final CycleMark mark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final period = mark.kind == CycleMarkKind.period;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(
            period ? Icons.water_drop : Icons.water_drop_outlined,
            size: 18,
            color: t.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                period ? 'Marked as a period day' : 'Marked as spotting',
                if (mark.flow case final flow?) 'flow: ${flow.word.toLowerCase()}',
                if (mark.backfilled) 'entered after the fact',
              ].join(' · '),
              style: TextStyle(color: t.textSecondary, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your note', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.45)),
        ],
      ),
    );
  }
}

/// Where the user is in their cycle, and the one line of prediction — or the one
/// line of refusal, in the same size type and the same tone.
///
/// The prediction lives in the Cycle view with its basis; this is the summary, and
/// it says which tab the working is on. A refusal is not dressed up differently:
/// for a lot of people "not enough cycles yet" is the correct answer, and it would
/// be dishonest to print it as a warning under a window that other people get.
class _CycleCard extends StatelessWidget {
  const _CycleCard({
    required this.position,
    required this.forecast,
    required this.loading,
    required this.today,
  });

  final CyclePosition position;
  final CycleForecast forecast;
  final bool loading;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final known = position.known;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where you are', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(
            switch (position) {
              CyclePosition(dayNumber: final day?) => 'Cycle day $day',
              CyclePosition(daysSinceStart: final days?, periodStart: final start?)
                  when days > CyclePosition.meaningfulWithinDays =>
                'Your last period started $days days ago, on ${dayLabel(start)}.',
              _ => 'No period recorded yet.',
            },
            style: TextStyle(color: t.textPrimary, fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            known
                ? 'Counted from the first day of your last period.'
                : position.daysSinceStart != null
                    ? 'A cycle day stops being a fact after two months, so the app stops showing one '
                        'and tells you the date instead.'
                    : 'Record a period day and this counts from it.',
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
          ),
          if (!loading) ...[
            const SizedBox(height: 14),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 12),
            Text(
              _predictionLine(),
              style: TextStyle(
                color: forecast.hasWindow ? t.textPrimary : t.textSecondary,
                fontSize: 14,
                fontWeight: forecast.hasWindow ? FontWeight.w700 : FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => context.go('/cycle'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                forecast.hasWindow
                    ? 'See the cycles it is based on'
                    : 'See why, on the ${AppTextScope.of(context).navPatterns} tab',
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One line: the window, or a count of months, or the refusal's own title.
  String _predictionLine() {
    // Bound to a local so the pattern match promotes it — a field is not
    // promoted, and the alternative is a cast that would hide a new subtype.
    final CycleForecast current = forecast;
    switch (current) {
      case ForecastWindow():
        final label = windowLabel(current.earliest, current.latest, inYear: today.year);
        return current.daysLate(today) > 0
            ? 'Next period was due $label'
            : 'Next period: $label';
      case ForecastPerimenopause():
        final months = current.monthsSinceLastPeriod;
        return months == 0
            ? 'No prediction in perimenopause mode.'
            : 'Last period: $months ${months == 1 ? 'month' : 'months'} ago';
      case ForecastUnavailable():
        return 'No prediction: ${_lowerFirst(current.title)}';
    }
  }

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: t.accent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: t.accent, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's central promise, at the size somebody scrolls past.
///
/// It was four lines of prose at the bottom of this screen. Nobody reads four lines
/// of prose on the screen they open twice a day, and a paragraph a user has learned
/// to skip is worse than no paragraph: it makes the claim look like boilerplate.
///
/// So this is the claim as one line with a way to check it. The full version — with
/// the internet permission read out of this phone rather than asserted, and the
/// keystore's own answer beside it — is on Settings, one tap away, which is where
/// someone who actually wants to verify it goes.
class _TrustNote extends StatelessWidget {
  const _TrustNote({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surfaceRaised,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 17, color: t.accentSoft),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'No internet permission',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
