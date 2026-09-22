import 'package:flutter/material.dart';

import '../../core/cycle/cycle_forecast.dart';
import '../../core/cycle/cycle_series.dart';
import '../../core/cycle/cycle_settings.dart';
import '../../core/cycle/window_provenance.dart';
import '../../core/log/day_key.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';

/// The prediction, drawn so the working is visible.
///
/// Three rules this card obeys, and they are why it is not a one-line widget:
///
///  * **A range is drawn as a range.** There is no single emphasised date, no
///    countdown to a day, and no confidence percentage — the two ends of the
///    window are the two facts, and they get the same weight.
///  * **The basis is always on the card.** Every prediction carries the cycle
///    lengths it came from, drawn as chips, so "why does it think that" is
///    answered before it is asked.
///  * **A refusal is a result, not an error state.** "Your cycles vary too much
///    for a useful prediction" is rendered with the same typography and the same
///    calm as a window, because for a lot of people it is the *correct* answer
///    and it is the one thing other apps will not say.
class PredictionCard extends StatelessWidget {
  const PredictionCard({
    super.key,
    required this.forecast,
    required this.today,
    this.provenance,
  });

  final CycleForecast forecast;
  final DateTime today;

  /// Why the window is where it is: which recorded cycles set its ends, and what
  /// the last finished cycle changed. Null — or absent, in a test that only cares
  /// about the prediction — draws nothing.
  final WindowProvenance? provenance;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Bound to a local so the pattern match promotes it: `forecast` is a field,
    // and Dart does not promote fields.
    final CycleForecast current = forecast;
    // Only a window has ends to explain, whatever the caller passed.
    final window = current is ForecastWindow ? current : null;
    final provenance = this.provenance;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(forecast: current),
          const SizedBox(height: 16),
          switch (current) {
            ForecastWindow() => _Window(window: current, today: today),
            ForecastPerimenopause() => _PerimenopauseBody(forecast: current),
            ForecastUnavailable() => _UnavailableBody(forecast: current),
          },
          if (forecast.series.lengths.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 14),
            _Basis(series: forecast.series),
          ],
          if (provenance != null && window != null) ...[
            const SizedBox(height: 16),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 14),
            _Provenance(provenance: provenance, window: window),
          ],
          if (forecast.methodNote case final note?) ...[
            const SizedBox(height: 14),
            _MethodNote(note),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.forecast});

  final CycleForecast forecast;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = forecast is ForecastPerimenopause
        ? 'Since your last period'
        : 'Next period';

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            forecast.hasWindow ? Icons.insights_outlined : Icons.info_outline,
            size: 18,
            color: t.accentSoft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label.toUpperCase(), style: _eyebrow(t)),
        ),
        if (forecast.hasWindow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.border),
            ),
            child: Text('range, not a date', style: _eyebrow(t, size: 10)),
          ),
      ],
    );
  }
}

TextStyle _eyebrow(AppTokens t, {double size = 11.5}) => TextStyle(
      color: t.textFaint,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    );

/// The prediction itself: the two ends of the window, and where today sits.
class _Window extends StatelessWidget {
  const _Window({required this.window, required this.today});

  final ForecastWindow window;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final earliest = window.earliest;
    final latest = window.latest;
    final open = window.isOpenOn(today);
    final late = window.daysLate(today);
    final until = window.daysUntilOpen(today);

    final status = late > 0
        ? 'Past the window by $late ${late == 1 ? 'day' : 'days'}'
        : open
            ? 'Inside the window now'
            : until == 1
                ? 'Opens tomorrow'
                : 'Opens in $until days';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          windowLabel(earliest, latest, inYear: today.year),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: late > 0 || open ? t.accent : t.accentSoft,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                style: TextStyle(
                  color: late > 0 ? t.accent : t.textSecondary,
                  fontSize: 13.5,
                  fontWeight: late > 0 ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _explanation(window, late: late, open: open),
          style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
        ),
      ],
    );
  }

  /// What it means, in the case that applies. The late wording deliberately does
  /// not contain a single day the app expects — late is described as a fact about
  /// the record, never as a reason to move the window.
  String _explanation(ForecastWindow window, {required int late, required bool open}) {
    final width = window.widthDays;
    // The regular-mode limit is the yardstick for "is this wide?": past it, the
    // width has earned a sentence of its own.
    final wide = width > CycleMode.regular.spreadLimitDays!;

    if (late > 0) {
      return 'Your cycles run ${window.series.shortest}–${window.series.longest} '
          'days, and it has been ${_sinceLast(window)} since your last period '
          'started. A late cycle is left as it is: nothing here gets re-dated to '
          'keep the pattern tidy.';
    }
    if (open) {
      return 'That is the range your own cycles point at, and today is inside it. '
          'It is still a range — the day it starts is not something this record '
          'can tell you.';
    }
    if (wide) {
      // Said plainly rather than apologised for: in irregular mode the width is
      // the feature, and a person with PCOD has usually been told their own
      // record is the problem.
      return 'A window $width days wide is deliberate in irregular mode. Narrower '
          'would be more confident and less true.';
    }
    return 'Built from the shortest and longest of your recent cycles, so it widens '
        'and narrows as your record does.';
  }

  String _sinceLast(ForecastWindow window) {
    // Computed from the last start rather than stored, so it cannot drift out of
    // step with the window beside it. Calendar days, not 24-hour blocks: a
    // difference in elapsed hours is a day short across a clock change.
    final start = window.series.lastStart;
    final elapsed = start == null ? 0 : DayKey.daysBetween(start, today);
    return '$elapsed ${elapsed == 1 ? 'day' : 'days'}';
  }
}

class _PerimenopauseBody extends StatelessWidget {
  const _PerimenopauseBody({required this.forecast});

  final ForecastPerimenopause forecast;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final months = forecast.monthsSinceLastPeriod;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          forecast.daysSinceLastPeriod < 60
              ? forecast.sinceLabel
              : '$months ${months == 1 ? 'month' : 'months'} since your period',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Perimenopause mode shows no window, because in this stage cycles '
          'lengthen, shorten and skip — a predicted date would be a guess wearing '
          'a date\'s clothes.',
          style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 12),
        Text(
          forecast.periodsInLastYear == 0
              ? 'No periods recorded in the last twelve months.'
              : '${forecast.periodsInLastYear} '
                  '${forecast.periodsInLastYear == 1 ? 'period' : 'periods'} recorded '
                  'in the last twelve months. That count is what is worth taking to '
                  'an appointment.',
          style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.45),
        ),
      ],
    );
  }
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody({required this.forecast});

  final ForecastUnavailable forecast;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          forecast.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.25),
        ),
        const SizedBox(height: 10),
        Text(
          forecast.reason,
          style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
        ),
        if (forecast.whatWouldHelp case final help?) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(Icons.arrow_right_alt, size: 16, color: t.accentSoft),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  help,
                  style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The chips: one per cycle the window was built from, older to newer.
///
/// On screen rather than behind a "why?" tap, because the arithmetic is the whole
/// claim. A card that says "12–16 October" and hides the six numbers underneath
/// it is asking to be trusted; this one can be checked.
class _Basis extends StatelessWidget {
  const _Basis({required this.series});

  final CycleSeries series;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shortest = series.shortest;
    final longest = series.longest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What this is based on', style: _eyebrow(t)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final length in series.lengths)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: length == longest && length != shortest
                      ? t.surfaceRaised
                      : t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: length == shortest || length == longest
                        ? t.accentSoft
                        : t.border,
                  ),
                ),
                child: Text(
                  '$length',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${series.describeBasis()} Days, oldest to newest.',
          style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.45),
        ),
        if (series.lastPeriodLengthDays case final days?) ...[
          const SizedBox(height: 4),
          Text(
            'Your last period lasted $days ${days == 1 ? 'day' : 'days'}.',
            style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// What moved the window last, and which recorded days set its ends.
///
/// The card above it says where the window is; this says why, in the terms the
/// record is actually made of — days that were logged. It is drawn as two named
/// ends and a sentence rather than as a comparison of dates, because a new period
/// start moves every date in the window by definition: the only thing that can
/// genuinely change is the shape, and the two recorded cycles responsible for it.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.provenance, required this.window});

  final WindowProvenance provenance;
  final ForecastWindow window;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = provenance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What moved it last', style: _eyebrow(t)),
        const SizedBox(height: 10),
        Text(
          p.headline,
          style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.5),
        ),
        for (final change in p.changes) ...[
          const SizedBox(height: 6),
          Text(
            change,
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.5),
          ),
        ],
        const SizedBox(height: 12),
        _EndOwner(
          label: 'First day',
          date: window.earliest,
          anchor: p.anchor,
          span: p.shortest,
          tied: p.shortestCount > 1,
          which: 'shortest',
          inYear: p.inYear,
        ),
        const SizedBox(height: 8),
        _EndOwner(
          label: 'Last day',
          date: window.latest,
          anchor: p.anchor,
          span: p.longest,
          tied: p.longestCount > 1,
          which: 'longest',
          inYear: p.inYear,
        ),
        const SizedBox(height: 10),
        Text(
          'The ends come from those two cycles and nothing else: the shortest sets '
          'the first day, the longest the last. Logging a period that changes '
          'either one moves the window, and this card says which day did it.',
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

/// One end of the window, with the recorded cycle it came from.
class _EndOwner extends StatelessWidget {
  const _EndOwner({
    required this.label,
    required this.date,
    required this.anchor,
    required this.span,
    required this.tied,
    required this.which,
    required this.inYear,
  });

  final String label;
  final DateTime date;
  final DateTime anchor;
  final CycleSpan span;

  /// True when more than one cycle in the basis has this length, in which case
  /// the row says "one of" rather than claiming a unique owner it does not have.
  final bool tied;
  final String which;
  final int inYear;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final after = DayKey.daysBetween(anchor, date);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${dayLabel(date, inYear: inYear)}  ',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '$after ${after == 1 ? 'day' : 'days'} after '
                      '${shortDayLabel(anchor)} — ${tied ? 'one of your' : 'your'} '
                      '$which ${tied ? 'cycles' : 'cycle'}, ${span.label}'
                      '${span.backfilled ? ', entered later' : ''}',
                ),
              ],
            ),
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _MethodNote extends StatelessWidget {
  const _MethodNote(this.note);

  final String note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.medication_outlined, size: 15, color: t.textFaint),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            note,
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
          ),
        ),
      ],
    );
  }
}
