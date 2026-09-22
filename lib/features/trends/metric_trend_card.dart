import 'package:flutter/material.dart';

import '../../core/log/log_models.dart';
import '../../core/metrics/metric_models.dart';
import '../../core/theme/app_theme.dart';

/// The measurements, over the same window the comparison uses.
///
/// The shape is a sparkline and the facts are in words beside it, in that order of
/// trust: a line drawn from six readings and a line drawn from sixty look identical,
/// so the count is printed, the axis is labelled with the real values, and anything
/// under [minimumReadings] gets a sentence instead of a line.
///
/// Every quantity here is drawn from what was actually recorded. There is no
/// interpolation across gaps — a missing week is a gap in the line, not a straight
/// segment through it — and no projection beyond the last reading.
class MetricTrendCard extends StatelessWidget {
  const MetricTrendCard({
    super.key,
    required this.days,
    required this.prefs,
    this.minimumReadings = 5,
  });

  /// The six-month window, oldest or newest first — this sorts.
  final List<DayLog> days;

  final MetricPrefs prefs;
  final int minimumReadings;

  @override
  Widget build(BuildContext context) {
    final enabled = prefs.ordered;
    if (enabled.isEmpty) return const _NothingOn();

    final ordered = [...days]..sort((a, b) => a.day.compareTo(b.day));
    final sections = [
      for (final kind in enabled) _Series.from(kind, ordered),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: context.tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, size: 18, color: context.tokens.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The measurements you keep',
                  style: TextStyle(
                    color: context.tokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Readings you recorded in the last six months. A gap in a line is a day '
            'you did not measure, and it is left as a gap rather than filled in.',
            style: TextStyle(
              color: context.tokens.textSecondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          for (final series in sections) ...[
            const SizedBox(height: 18),
            _SeriesBlock(series: series, minimumReadings: minimumReadings),
          ],
        ],
      ),
    );
  }
}

/// One reading and the day it belongs to.
///
/// Carried together rather than as two parallel lists, because the day is what
/// positions the point on the axis and a list that drifted out of step with the
/// values would draw an honest number in a dishonest place.
typedef _Reading = ({DateTime day, DayMetric metric});

/// One metric's readings over the window, with the gap positions kept.
class _Series {
  const _Series({
    required this.kind,
    required this.readings,
    required this.firstDay,
    required this.lastDay,
  });

  /// Every reading in the window, in day order.
  final List<_Reading> readings;

  /// The first and last *day in the window*, not the first and last reading. The
  /// line is drawn across the window so that a month with no measurements looks
  /// like a month with no measurements rather than a tightly packed fortnight.
  final DateTime firstDay;
  final DateTime lastDay;

  final MetricKind kind;

  static _Series from(MetricKind kind, List<DayLog> ordered) {
    final readings = <_Reading>[
      for (final day in ordered)
        if (day.metrics[kind] case final metric?) (day: day.day, metric: metric),
    ];
    return _Series(
      kind: kind,
      readings: readings,
      firstDay: ordered.isEmpty ? DateTime(2000) : ordered.first.day,
      lastDay: ordered.isEmpty ? DateTime(2000) : ordered.last.day,
    );
  }

  bool get isEmpty => readings.isEmpty;
  int get count => readings.length;

  Iterable<double> get _values => readings.map((r) => r.metric.value);

  double get lowest => _values.reduce((a, b) => a < b ? a : b);
  double get highest => _values.reduce((a, b) => a > b ? a : b);
  double get mean => _values.fold(0.0, (sum, v) => sum + v) / readings.length;

  double get first => readings.first.metric.value;
  double get last => readings.last.metric.value;

  /// The change from the first reading to the last, or null when there is only
  /// one. Deliberately not "per day" or "per week": a rate from irregular readings
  /// is a number the app would be inventing.
  double? get change => readings.length < 2 ? null : last - first;
}

class _SeriesBlock extends StatelessWidget {
  const _SeriesBlock({required this.series, required this.minimumReadings});

  final _Series series;
  final int minimumReadings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          series.kind.title,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        if (series.isEmpty)
          Text(
            'Nothing recorded in this window. The line appears when you log '
            'something — the app will not draw an empty chart to fill the space.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
          )
        else ...[
          Text(
            _summary(series),
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 10),
          if (series.count < minimumReadings)
            Text(
              _tooFew(series, minimumReadings),
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            )
          else
            _Sparkline(series: series),
        ],
      ],
    );
  }
}

String _summary(_Series series) {
  if (series.kind == MetricKind.mucus) {
    return '${series.count} ${series.count == 1 ? 'day' : 'days'} described.';
  }  final parts = [
    '${series.count} ${series.count == 1 ? 'reading' : 'readings'}',
    'lowest ${series.kind.format(series.lowest)}',
    'highest ${series.kind.format(series.highest)}',
    'mean ${series.kind.format(series.mean)}',
  ];
  if (series.change case final change?) {
    // Signed, because the direction is the only thing a person looks for and an
    // unsigned "0.8 kg" beside an arrow would be read as an increase either way.
    // [MetricKind.format] already carries the unit, so there is none to add here.
    final sign = change > 0 ? '+' : (change < 0 ? '−' : '');
    parts.add(
      'from ${series.kind.format(series.first)} to '
      '${series.kind.format(series.last)} '
      '($sign${series.kind.format(change.abs())})',
    );
  }
  return '${parts.join(', ')}.';
}

String _tooFew(_Series series, int need) {
  final have = series.count;
  if (series.kind == MetricKind.mucus) {
    // Mucus is a description, not a quantity: a line through Dry/Sticky/Wet would
    // be a fertility claim drawn as an axis, which this app does not make.
    return 'Descriptions are listed as counts rather than drawn as a line: Dry, '
        'Sticky and Wet are words, and a line through them would be read as an '
        'ovulation signal the app does not estimate.';
  }
  return '$have ${have == 1 ? 'reading is' : 'readings are'} not enough to draw a '
      'line from — $need is the floor, because a shape drawn from two points is a '
      'straight line dressed up as a trend.';
}

/// A polyline over the window, with the axis labelled by the real values.
///
/// The two numbers at the ends of the axis are the point of this widget: they are
/// what stops a vertical wiggle of three kilograms from reading as a cliff.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.series});

  final _Series series;

  static const double height = 74;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final top = series.highest;
    final bottom = series.lowest;
    // A flat series has no range to scale into. Drawing it down the middle is the
    // honest picture of "it did not change"; dividing by zero is not.
    final span = (top - bottom).abs() < 0.0001 ? null : top - bottom;

    // The height is pinned on the outside. `CrossAxisAlignment.stretch` and a
    // `Spacer` both need a bounded vertical axis, and this card sits in a Column
    // inside a scrolling page, where the vertical constraint is unbounded — so
    // without this the axis labels get an infinite height and the whole screen
    // throws the first time a line is actually drawn.
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  series.kind.format(top),
                  style: TextStyle(color: t.textFaint, fontSize: 10.5),
                ),
                if (span == null)
                  Text(
                    'no change',
                    style: TextStyle(color: t.textFaint, fontSize: 10.5),
                  )
                else
                  Text(
                    series.kind.format(bottom),
                    style: TextStyle(color: t.textFaint, fontSize: 10.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CustomPaint(
              painter: _SparklinePainter(
                values: [for (final r in series.readings) r.metric.value],
                days: [for (final r in series.readings) r.day],
                firstDay: series.firstDay,
                lastDay: series.lastDay,
                span: span,
                line: t.textSecondary,
                faint: t.border,
              ),
              // A screen reader gets the summary text above rather than a
              // description of a picture it cannot use.
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.days,
    required this.firstDay,
    required this.lastDay,
    required this.span,
    required this.line,
    required this.faint,
  });

  final List<double> values;
  final List<DateTime> days;
  final DateTime firstDay;
  final DateTime lastDay;

  /// Null when the series is flat.
  final double? span;

  final Color line;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final totalDays = lastDay.difference(firstDay).inDays;
    double x(int index) {
      if (totalDays <= 0) return size.width / 2;
      final offset = days[index].difference(firstDay).inDays / totalDays;
      return offset * size.width;
    }

    double y(double value) {
      if (span == null) return size.height / 2;
      final top = values.reduce((a, b) => a > b ? a : b);
      // Inset by the dot radius so the highest and lowest points are not clipped.
      const inset = 5.0;
      final usable = size.height - inset * 2;
      return inset + (top - value) / span! * usable;
    }

    // A baseline and a zero line only when there is a range; otherwise the single
    // horizontal line through the middle is the picture.
    final baseline = Paint()
      ..color = faint
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baseline,
    );

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(x(i), y(values[i]));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    // One dot per reading, so the days that were measured are countable off the
    // picture. A line drawn without them hides where the gaps are.
    final dot = Paint()..color = line;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), 2.6, dot);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.span != span ||
      old.firstDay != firstDay ||
      old.lastDay != lastDay;
}

class _NothingOn extends StatelessWidget {
  const _NothingOn();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
            'No measurements switched on',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Weight, sleep, activity, water, basal temperature, cervical mucus, '
            'waist and blood pressure are all off until you turn one on. Nothing '
            'is recorded in the background, and switching one off leaves the '
            'readings you already made in your record.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}
