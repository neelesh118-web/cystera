import 'package:flutter/material.dart';

import '../../core/cycle/cycle_series.dart';
import '../../core/theme/app_theme.dart';

/// The last few cycles drawn as lengths, so a person can *see* the spread rather
/// than read three numbers and guess.
///
/// The card refuses below three completed cycles, and it prints its own basis —
/// how many cycles, the shortest, the longest, the spread — because a bar chart is
/// the most persuasive thing on this screen and the least able to say what it left
/// out. A chart drawn from two cycles looks exactly as authoritative as one drawn
/// from twelve, and the difference is the whole question.
///
/// It deliberately does not draw a line through the bars or project the next one.
/// Bars are a record of what happened; a trend line is a claim about what will.
class CycleLengthCard extends StatelessWidget {
  const CycleLengthCard({super.key, required this.series, this.minimumCycles = 3});

  final CycleSeries series;

  /// The same floor the prediction uses. Not a setting: a chart that drew a
  /// "pattern" from two cycles while the prediction refused to would be the app
  /// disagreeing with itself in public.
  final int minimumCycles;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lengths = series.recentLengthDays;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_outlined, size: 18, color: t.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'How long each cycle ran',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A cycle length is the gap between one period starting and the next. '
            'The cycle you are in now has no length yet, so it is not on the chart.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          if (lengths.length < minimumCycles)
            _TooFew(
              have: lengths.length,
              need: minimumCycles,
              average: series.averageDays,
            )
          else ...[
            _Bars(lengths: lengths, average: series.averageDays!),
            const SizedBox(height: 12),
            Text(
              series.describeBasis(),
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

/// The refusal, which names the number that would change it. "Not enough data" is
/// a sentence that tells someone nothing they can act on.
class _TooFew extends StatelessWidget {
  const _TooFew({required this.have, required this.need, this.average});

  final int have;
  final int need;
  final int? average;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final body = switch (have) {
      0 => 'No cycles are finished yet, so there is nothing to plot. The first bar '
          'appears once a second period is recorded and the gap between them is a '
          'fact.',
      1 => average == null
          ? 'One cycle is on record. One is not a spread — it is a single number, '
              'and drawing it as a chart would imply a pattern that is not there. '
              'Two more will fill this in.'
          : 'One cycle is on record, and it ran $average days. One is not a spread '
              '— two more will fill this in.',
      _ => '$have cycles are on record. Two could both be unusual, so the chart '
          'waits for $need before drawing a pattern.',
    };

    return Text(
      body,
      style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
    );
  }
}

/// Plain bars, sized to the longest cycle so the tallest one fills the space.
///
/// Laid out with Containers rather than a `CustomPainter`: there are at most six
/// bars, the whole picture is a column of rectangles, and a painter would be more
/// code that no widget test can read. It also lets the numbers sit inside the bars,
/// where they are impossible to read off the wrong bar.
class _Bars extends StatelessWidget {
  const _Bars({required this.lengths, required this.average});

  final List<int> lengths;
  final int average;

  /// The tallest bar, with a floor so a record of one 2-day cycle cannot make a
  /// 60-pixel bar out of a 5-pixel range.
  static const double _maxHeight = 130;
  static const double _minHeight = 18;

  @override
  Widget build(BuildContext context) {
    final longest = lengths.reduce((a, b) => a > b ? a : b);
    final shortest = lengths.reduce((a, b) => a < b ? a : b);
    // The scale runs from zero rather than from the shortest, because bars that
    // start at a non-zero baseline make a 28-day and a 30-day cycle look like a
    // three-fold difference.
    final scale = longest == 0 ? 1.0 : _maxHeight / longest;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < lengths.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _Bar(
              // Oldest first, so the chart reads left to right like a calendar.
              length: lengths[i],
              height: (lengths[i] * scale).clamp(_minHeight, _maxHeight),
              isShortest: lengths[i] == shortest,
              isLongest: lengths[i] == longest,
              average: average,
              older: i == 0,
              newer: i == lengths.length - 1,
            ),
          ),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.length,
    required this.height,
    required this.isShortest,
    required this.isLongest,
    required this.average,
    required this.older,
    required this.newer,
  });

  final int length;
  final double height;
  final bool isShortest;
  final bool isLongest;
  final int average;
  final bool older;
  final bool newer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // The average is drawn in the accent colour so the one bar at the middle of
    // the range is findable without a legend. Ties go to neither, and the sentence
    // under the chart still says the number.
    final atAverage = length == average && !isShortest && !isLongest;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$length',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: atAverage ? t.accent : t.border,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          older ? 'oldest' : (newer ? 'newest' : ''),
          style: TextStyle(color: t.textFaint, fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ],
    );
  }
}
