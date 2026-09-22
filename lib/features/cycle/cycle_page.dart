import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cycle/cycle_backtest.dart';
import '../../core/cycle/cycle_summary.dart';
import '../../core/cycle/window_provenance.dart';
import '../../core/log/log_controller.dart';
import '../../core/log/log_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import '../../core/widgets/page_scaffold.dart';
import '../log/backfill_sheet.dart';
import 'cycle_history_card.dart';
import 'cycle_settings_section.dart';
import 'cycle_summary_card.dart';
import 'prediction_card.dart';

/// What the record says about the cycle, and what it refuses to say.
///
/// Generic trackers respond to an irregular cycle by quietly rewriting the record
/// until the prediction fits. That is the most damaging thing a cycle app does to
/// someone with PCOD/PCOS, because the record is what they came for and a late
/// cycle is information rather than an error. So this screen shows the periods
/// that were recorded, says how long each one lasted, marks which were entered
/// after the fact — and, when it does predict, shows the window *and* the cycle
/// lengths it was built from, on the same card.
class CyclePage extends StatelessWidget {
  const CyclePage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<LogController>();
    final runs = log.series.runs;
    final forecast = log.forecast;

    return PageScaffold(
      title: 'Cycle',
      subtitle: runs.isEmpty
          ? 'No cycles recorded yet, so there is nothing to predict from.'
          : '${runs.length} ${runs.length == 1 ? 'period' : 'periods'} recorded. '
              'Everything below is either what you logged or the arithmetic you '
              'can check.',
      children: [
        if (log.loading)
          const _LoadingCard()
        else
          PredictionCard(
            forecast: forecast,
            today: log.today,
            provenance: windowProvenance(
              marks: log.cycleMarks,
              today: log.today,
              settings: log.settings,
            ),
          ),
        // Below the card, never above it: the window for the cycle in progress is
        // the thing to act on, and this is the app's own record being held up to
        // the same measure a user would hold it to.
        if (!log.loading && runs.length >= 2)
          CycleHistoryCard(
            backtest: cycleBacktest(
              marks: log.cycleMarks,
              today: log.today,
              settings: log.settings,
            ),
            today: log.today,
            methodNote: forecast.methodNote,
          ),
        // Below the history card and above the raw list: this is the summary to
        // *bring* somewhere, and the list under it is what the summary was built
        // from. Shown only once something is recorded, because on an empty record
        // the refusal would be a second way of saying what `_EmptyRecord` says.
        if (!log.loading && runs.isNotEmpty)
          CycleSummaryCard(
            summary: CycleSummary.from(log.cycleMarks, today: log.today),
          ),
        if (runs.isNotEmpty) _RecordedRuns(runs: runs),
        if (runs.isEmpty) const _EmptyRecord(),
        OutlinedButton.icon(
          onPressed: () => showBackfillSheet(context),
          icon: const Icon(Icons.event_repeat_outlined, size: 20),
          label: const Text('Record a period I did not log'),
        ),
        CycleInputsCard(),
      ],
    );
  }
}

/// Shown while the record is being read, in place of a card that would otherwise
/// announce "no periods recorded yet" to someone who has years of them.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

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
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.accentSoft),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Reading your record…',
              style: TextStyle(color: t.textSecondary, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The periods themselves, newest first, with what is known about each.
class _RecordedRuns extends StatelessWidget {
  const _RecordedRuns({required this.runs});

  final List<PeriodRun> runs;

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
          Text('Recorded periods', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Newest first. A period still being logged is shown as ongoing rather than given a length '
            'it has not reached yet.',
            style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          for (final run in runs.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          run.start == run.end
                              ? shortDayLabel(run.start)
                              : windowLabel(run.start, run.end),
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            run.ongoing ? 'ongoing' : '${run.lengthDays} days',
                            if (run.backfilled) 'entered later',
                          ].join(' · '),
                          style: TextStyle(
                            color: run.backfilled ? t.accent : t.textFaint,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (runs.length > 6)
            Text(
              'Showing the last 6 of ${runs.length}. Older ones are still in your '
              'record, and in your backup.',
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
            ),
        ],
      ),
    );
  }
}

class _EmptyRecord extends StatelessWidget {
  const _EmptyRecord();

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
          Row(
            children: [
              Icon(Icons.calendar_month_outlined, size: 18, color: t.accentSoft),
              const SizedBox(width: 10),
              // Expanded rather than sized to its content: this is a fixed-height
              // row, so a longer string — another language, or a larger system
              // font scale — must wrap rather than paint outside the card.
              Expanded(
                child: Text(
                  'Starting the record',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Mark the first day of a period on the Log tab and the count starts '
            'there. Nothing on this screen is estimated, so until then it stays '
            'empty rather than filling itself in.',
            style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}
