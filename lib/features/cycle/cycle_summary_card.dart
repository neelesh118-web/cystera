import 'package:flutter/material.dart';

import '../../core/cycle/cycle_summary.dart';
import '../../core/i18n/app_text.dart';
import '../../core/theme/app_theme.dart';

/// The last twelve months, in the terms a doctor asks in.
///
/// It sits below the history card on purpose. The window the app gave is the thing
/// to act on; this is the thing to *bring* — the figures a clinician asks for in the
/// first two minutes of an appointment, which most people try to remember and get
/// wrong, and which the record can answer exactly.
///
/// Three rules, and the card is not much more than them:
///
///  * **The thresholds are printed, not applied.** `21–35 days` and `fewer than 8
///    starts in a year` are what a clinician checks. They appear as a note beside the
///    user's own numbers, and the app does not put a tick, a warning colour or a
///    verdict against any row. The distance between showing someone a threshold and
///    crossing it off for them is the whole point of this app.
///  * **The refusal is a result, not an error.** Below three completed cycles the
///    year cannot be described, so the card says so and names the floor — the same
///    three the prediction uses, so the two cards can never appear to disagree.
///  * **"Since the last period start" is not a cycle length.** It is shown even when
///    the rest is refused, because it is the number someone with irregular cycles
///    actually opens the app for, and because it is a fact rather than a summary: the
///    cycle in progress has no length until it ends, and calling this one would be
///    the error every other tracker makes.
class CycleSummaryCard extends StatelessWidget {
  const CycleSummaryCard({super.key, required this.summary});

  final CycleSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);

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
            text.summaryHeading,
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          if (summary.hasEnough) ...[
            _Row(
              label: text.summaryStartsLabel,
              value: '${summary.startsInYear}',
              emphasise: true,
            ),
            _Row(
              label: text.summaryCyclesLabel,
              value: '${summary.lengths.length}',
            ),
            if (summary.medianDays case final median?)
              _Row(
                label: text.summaryMedianLabel,
                value: text.summaryDaysValue(median),
              ),
            if (summary.shortestDays case final shortest?)
              if (summary.longestDays case final longest?)
                _Row(
                  label: text.summaryRangeLabel,
                  value: text.summaryRangeValue(shortest, longest),
                ),
            _Row(
              label: text.summaryOutsideLabel,
              value: text.summaryOutsideValue(
                summary.overLongThreshold,
                summary.underShortThreshold,
              ),
            ),
          ] else
            Text(
              text.summaryRefusal(summary.lengths.length),
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
            ),
          // Always shown, in both states. See the note above the class.
          if (summary.daysSinceLastStart case final since?)
            _Row(
              label: text.summarySinceLastLabel,
              value: text.summaryDaysValue(since),
            ),
          const SizedBox(height: 10),
          Text(
            text.summaryThresholdsNote,
            style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// One label and its number.
///
/// A fixed-width label column rather than a sentence, so the figures line up and can
/// be read down the page in an appointment — and so translation moves the words
/// without moving the numbers around them.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasise = false});

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              label,
              style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.35),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: emphasise ? 15 : 13,
                height: 1.35,
                fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
