import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_backtest.dart';
import '../../core/log/day_key.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';

/// The last six cycles, held against what the app said at the time.
///
/// This is the screen's answer to the question every tracker hopes nobody asks:
/// *was the prediction any good?* It is drawn as six rows rather than as a line,
/// a score or a percentage, because those are the shapes that hide the two things
/// that matter here:
///
///  * **The rows where the app refused are rows too.** A cycle the app had no
///    window for is drawn with its own sentence, not dropped, and the count of
///    "how did it do" is over the cycles that had a window — said out loud rather
///    than quietly redivided.
///  * **Every row carries its own numbers.** The bar shows the window, the dot
///    shows the day the period actually started, and the line under them says
///    both dates and how many cycles the window was built from. A chart that only
///    shows the shape of the answer cannot be checked, and this app only ships
///    claims that can be.
///
/// It also never averages. The window drawn here is the shortest and longest of
/// the lengths that existed *at that moment*, which is what the app really showed
/// then — a mean would be a different, narrower window than anyone ever saw.
class CycleHistoryCard extends StatelessWidget {
  const CycleHistoryCard({
    super.key,
    required this.backtest,
    required this.today,
    this.methodNote,
  });

  final CycleBacktest backtest;

  /// For the year on a date label, and for nothing else.
  final DateTime today;

  /// The hormonal-contraception sentence from the card above, when there is one.
  final String? methodNote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = backtest.rows;

    // One axis for all six rows, so the bars and dots can be compared with each
    // other. A per-row scale would make a narrow window and a wide one look alike.
    final axis = CycleAxis.of(rows, today);

    // A run of refusals for the same reason is printed once. The early rows of
    // any record refuse for the same cause, and four copies of one sentence is
    // noise — but dropping the sentence for those rows would leave them with no
    // reason at all, so the ones that follow say where the reason is.
    final shown = <(CycleBacktestRow, bool)>[];
    String? previousRefusal;
    for (final row in rows) {
      final refusal = row.expectation is ExpectationRefused
          ? (row.expectation as ExpectationRefused).title
          : null;
      shown.add((row, refusal != null && refusal == previousRefusal));
      previousRefusal = refusal;
    }

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
          Text(
            rows.isEmpty
                ? 'CYCLE HISTORY'
                : 'THE LAST ${rows.length} ${rows.length == 1 ? 'CYCLE' : 'CYCLES'}',
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'How the window held up',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            backtest.hasChart
                ? 'Each row is a finished cycle. The bar is the window the app '
                    'gave before that period started — built only from what was on '
                    'record at the time — and the dot is the day it started. A row '
                    'with no bar is a cycle it would not predict for, which is a '
                    'result of its own.'
                : 'What the app would have said, held against what happened. There '
                    'is nothing to draw yet.',
            style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (!backtest.hasChart)
            Text(
              backtest.unavailable ?? 'Nothing to draw yet.',
              style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
            )
          else ...[
            for (final (row, repeated) in shown) ...[
              _HistoryRow(row: row, axis: axis, repeatRefusal: repeated),
              if (row != rows.last) const SizedBox(height: 14),
            ],
            const SizedBox(height: 18),
            // Same width as a track, so a month name sits under the gridline it
            // names rather than under the card.
            Row(
              children: [
                Expanded(child: _AxisLabels(axis: axis, today: today)),
                const SizedBox(width: _verdictGap),
                const SizedBox(width: _verdictWidth),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 14),
            _Verdict(backtest: backtest),
            const SizedBox(height: 10),
            _Limits(backtest: backtest),
            if (methodNote case final note?) ...[
              const SizedBox(height: 12),
              Text(
                'These are guesses at your schedule too: $note',
                style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Margin at each end of the chart, in days. A week on either side of the
/// six cycles, which is enough for the markers to sit clear of the edges.
const int axisPaddingDays = 7;

/// The verdict column, and the gap before it. Named because the axis labels have
/// to be laid out to the same width as the tracks: a month name under a different
/// scale than the bar above it is worse than no label at all.
const double _verdictWidth = 92;
const double _verdictGap = 12;

/// How much room one month label needs: the 34pt box it is drawn in, plus a gap.
/// The axis thins its gridlines to this, so two labels can never be printed on
/// top of each other however narrow the phone is.
const double axisLabelExtent = 40;

/// The shared time axis behind every row.
///
/// Public because [CycleWindowTrack] is public and takes it: a test can find a
/// row by the dates it is drawing and check the geometry against this scale.
class CycleAxis {
  const CycleAxis({required this.from, required this.to, required this.months});

  final DateTime from;
  final DateTime to;

  /// The first of every month the axis spans.
  final List<DateTime> months;

  static CycleAxis of(List<CycleBacktestRow> rows, DateTime today) {
    if (rows.isEmpty) {
      return CycleAxis(from: today, to: today, months: const []);
    }
    var from = rows.first.start;
    var to = rows.first.nextStart;
    for (final row in rows) {
      final window = row.window;
      if (window != null) {
        if (window.earliest.isBefore(from)) from = window.earliest;
        if (window.latest.isAfter(to)) to = window.latest;
      }
      if (row.nextStart.isAfter(to)) to = row.nextStart;
    }

    // A margin at each end, so the newest period's dot and the oldest window's
    // bar are drawn where they belong instead of being clamped back inside the
    // card. An axis that ends exactly on its last fact deletes the mark that
    // fact is drawn with.
    from = DayKey.addDays(from, -axisPaddingDays);
    to = DayKey.addDays(to, axisPaddingDays);

    final months = <DateTime>[];
    var cursor = DateTime(from.year, from.month, 1);
    while (!cursor.isAfter(to)) {
      if (!cursor.isBefore(from)) months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return CycleAxis(from: from, to: to, months: months);
  }

  /// The gridlines that fit [width], as first-of-month days.
  ///
  /// Width-aware rather than a fixed number, because the same six cycles are 178
  /// points wide on a phone and 700 on a tablet: a count that reads well on one
  /// prints four month names on top of each other on the other. The tracks and
  /// the labels both ask this, so they cannot thin differently.
  List<DateTime> ticksFor(double width) {
    if (months.isEmpty || width <= 0) return const [];
    final room = (width / axisLabelExtent).floor().clamp(1, 24);
    final step = (months.length / room).ceil();
    return [for (var i = 0; i < months.length; i += step) months[i]];
  }

  /// Where [day] sits on the axis, from 0 to 1. Clamped, so a period that arrived
  /// a long way outside its window is drawn at the edge rather than off the card.
  double fraction(DateTime day) {
    final span = DayKey.daysBetween(from, to);
    if (span <= 0) return 0;
    return (DayKey.daysBetween(from, day) / span).clamp(0.0, 1.0);
  }

  String labelFor(DateTime tick, int currentYear) {
    final name = shortMonthName(tick.month);
    // The year appears on a January tick when the axis is not the current year's,
    // which is the only place a reader can lose track of which year they are in.
    if (tick.month == 1 && tick.year != currentYear) {
      return '$name ${tick.year % 100}';
    }
    return name;
  }
}

/// One cycle: the window, the day the period came, and the numbers behind both.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.row,
    required this.axis,
    required this.repeatRefusal,
  });

  final CycleBacktestRow row;
  final CycleAxis axis;

  /// True when the row directly above already gave this exact refusal.
  final bool repeatRefusal;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final window = row.window;
    final verdict = row.verdictLabel;
    final missed = verdict != null && row.arrivedInsideWindow == false;

    return Semantics(
      label: _spoken(row),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CycleWindowTrack(row: row, axis: axis),
                const SizedBox(height: 7),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: window == null
                            ? 'no window was given'
                            : 'expected ${shortWindowLabel(window.earliest, window.latest)}'
                                ' from ${window.basisCycles} '
                                '${window.basisCycles == 1 ? 'cycle' : 'cycles'}',
                      ),
                      TextSpan(
                        text: '  ·  started ${shortDayLabel(row.nextStart)}',
                      ),
                    ],
                  ),
                  style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
                ),
                if (row.expectation
                    case ExpectationRefused(:final title, :final reason)) ...[
                  const SizedBox(height: 4),
                  if (repeatRefusal)
                    Text(
                      'refused for the same reason as the row above',
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    )
                  else ...[
                    Text(
                      title,
                      style: TextStyle(
                        color: t.accentSoft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: _verdictGap),
          SizedBox(
            width: _verdictWidth,
            child: Text(
              verdict ?? 'not predicted',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: missed ? t.accent : t.textFaint,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: missed ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The row in words, for a screen reader. Built from the same numbers the row
  /// draws, so the two cannot drift apart.
  String _spoken(CycleBacktestRow row) {
    final window = row.window;
    final refusal = row.expectation is ExpectationRefused
        ? (row.expectation as ExpectationRefused).title
        : null;
    final parts = <String>[
      'Cycle starting ${dayLabel(row.start)}, ${row.actualLengthDays} days long.',
      if (window == null)
        // The reason, not just its absence: a screen reader gets the same fact
        // the row prints for everyone else.
        'No window was given for it${refusal == null ? '.' : ': $refusal.'}'
      else
        'Window ${dayLabel(window.earliest)} to ${dayLabel(window.latest)}, '
            'built from ${window.basisCycles} '
            '${window.basisCycles == 1 ? 'cycle' : 'cycles'}.',
      'Period started ${dayLabel(row.nextStart)}'
          '${row.verdictLabel == null ? '.' : ', ${row.verdictLabel}.'}',
    ];
    return parts.join(' ');
  }
}

/// The bar and the dot, on the shared axis.
///
/// Public so a widget test can find a row by the dates it is drawing and check
/// that the pixels sit where the axis says they should: a chart that quietly
/// misplaces its own bar would otherwise pass every assertion except being looked
/// at.
class CycleWindowTrack extends StatelessWidget {
  const CycleWindowTrack({super.key, required this.row, required this.axis});

  final CycleBacktestRow row;
  final CycleAxis axis;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final window = row.window;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Null axis and a zero-width layout both collapse to the same guard: a
        // chart drawn at zero width should be invisible, not NaN.
        if (width <= 0 || !width.isFinite) {
          return const SizedBox(height: _trackHeight);
        }
        double at(DateTime day) => axis.fraction(day) * width;

        return SizedBox(
          height: _trackHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final tick in axis.ticksFor(width))
                Positioned(
                  left: at(tick),
                  top: 1,
                  bottom: 1,
                  width: 1,
                  child: ColoredBox(color: t.border.withValues(alpha: 0.5)),
                ),
              // The day the cycle began — the point everything is measured from.
              Positioned(
                left: at(row.start),
                top: 1,
                bottom: 1,
                width: 1,
                child: ColoredBox(color: t.textFaint.withValues(alpha: 0.55)),
              ),
              if (window != null)
                Positioned(
                  left: at(window.earliest),
                  top: 8,
                  height: 11,
                  // At least six pixels, so a three-day window is still a bar
                  // rather than a line that reads as a drawing mistake.
                  width: math.max(6, at(window.latest) - at(window.earliest) + 1),
                  child: CycleWindowBar(
                    earliest: window.earliest,
                    latest: window.latest,
                  ),
                ),
              Positioned(
                left: (at(row.nextStart) - 5.5).clamp(0.0, math.max(0.0, width - 11)),
                top: 8,
                width: 11,
                height: 11,
                child: CyclePeriodDot(day: row.nextStart),
              ),
            ],
          ),
        );
      },
    );
  }

  static const double _trackHeight = 27;
}

/// The window, as the pill it is drawn as. Public so a widget test can hold the
/// rectangle it occupies against the axis the row is drawn on.
class CycleWindowBar extends StatelessWidget {
  const CycleWindowBar({super.key, required this.earliest, required this.latest});

  final DateTime earliest;
  final DateTime latest;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.accentSoft.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.accentSoft.withValues(alpha: 0.8)),
      ),
    );
  }
}

/// The day the period actually started: one dot, the same weight on every row.
class CyclePeriodDot extends StatelessWidget {
  const CyclePeriodDot({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.accent,
        shape: BoxShape.circle,
        // A ring in the card's own colour, so the dot stays readable where it
        // lands on top of the bar.
        border: Border.all(color: t.surface, width: 2),
      ),
    );
  }
}

/// The month names under the rows, on the same scale as the tracks.
class _AxisLabels extends StatelessWidget {
  const _AxisLabels({required this.axis, required this.today});

  final CycleAxis axis;

  /// The app's own clock, not `DateTime.now()`: the axis and the plan have to
  /// agree about what year it is.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ticks = axis.ticksFor(width);
        return SizedBox(
          height: 15,
          child: Stack(
            children: [
              for (final tick in ticks)
                if (axis.fraction(tick) * width >= _labelWidth / 2 &&
                    axis.fraction(tick) * width <= width - _labelWidth / 2)
                  // Skipped rather than nudged when it would start outside the
                  // track: a label shifted inward no longer sits under the day it
                  // names, and a month name in the wrong place is a wrong label.
                  Positioned(
                    left: axis.fraction(tick) * width - _labelWidth / 2,
                    width: _labelWidth,
                    child: CycleAxisLabel(
                      tick: tick,
                      label: axis.labelFor(tick, today.year),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

const double _labelWidth = 34;

/// One month name on the axis. Public so a test can weigh the drawn labels
/// against each other and against the scale they are drawn on.
class CycleAxisLabel extends StatelessWidget {
  const CycleAxisLabel({super.key, required this.tick, required this.label});

  final DateTime tick;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.tokens.textFaint, fontSize: 10.5),
    );
  }
}

/// The count, with the misses named and the refusals accounted for separately.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.backtest});

  final CycleBacktest backtest;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final summary = backtest.summary;
    final refused = backtest.rows.length - backtest.windowCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          Text(
            summary,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (summary == null)
          Text(
            'None of these cycles had a window to be held against — the app was '
            'refusing for the whole of this stretch, which is what the rows above '
            'say and why.',
            style: TextStyle(color: t.textPrimary, fontSize: 14, height: 1.5),
          ),
        if (refused > 0) ...[
          const SizedBox(height: 8),
          Text(
            refused == 1
                ? 'One of the ${backtest.rows.length} is left out of that count: '
                    'the app had no window to give for it at the time.'
                : '$refused of the ${backtest.rows.length} are left out of that '
                    'count: the app had no window to give for them at the time.',
            style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.45),
          ),
        ],
      ],
    );
  }
}

class _Limits extends StatelessWidget {
  const _Limits({required this.backtest});

  final CycleBacktest backtest;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      'A description of your record, not a score for the app: '
      '${backtest.rows.length} cycles is a handful, and every row above can be '
      'checked by hand. The cycle you are in now is not here — it has no ending '
      'yet — and its window is on the card above.',
      style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
    );
  }
}
