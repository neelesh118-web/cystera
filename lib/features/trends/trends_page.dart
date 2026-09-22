import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/labs/lab_controller.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/milestone_notice.dart';
import '../../core/widgets/page_scaffold.dart';
import '../labs/lab_section.dart';
import 'correlation_card.dart';
import 'cycle_length_card.dart';
import 'metric_trend_card.dart';
import 'mfg_section.dart';

/// When symptoms land in a cycle, and what the app refuses to say about it.
///
/// The hard part here is not the arithmetic, it is refusing to report it.
/// Correlation over a handful of days is noise, and a confident-looking finding
/// drawn from one bad month is exactly how a health app talks someone into a food
/// group they never needed to give up — so every finding on this screen has cleared
/// a gate whose thresholds, sample size and held-out days are printed beside it,
/// and a record that cannot support a finding gets a sentence saying what is
/// missing rather than a blank space.
class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key});

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame, because reading six months of days notifies listeners
    // and a notification during the build pass is how a tab that opens once throws
    // once. The screen is the thing that knows it needs the window: the log screen
    // never does, and it should not pay for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LogController>().loadTrends();
    });
  }

  @override
  Widget build(BuildContext context) {
    final log = context.watch<LogController>();
    final labs = context.watch<LabController>();
    final correlation = log.correlation;
    final reading = correlation == null && log.trendsError == null;

    return PageScaffold(
      title: 'Trends',
      subtitle: correlation == null
          ? (log.trendsError == null
              ? 'Reading the last six months of your record.'
              : 'Your record could not be read just now.')
          : 'The last six months of your record, and what it refuses to say.',
      children: [
        if (log.trendsError case final error?)
          _ErrorCard(message: error)
        else if (reading)
          const _LoadingCard()
        else if (correlation != null) ...[
          CorrelationCard(correlation: correlation),
          // Both charts read the same six-month window the comparison above does,
          // so they appear together and a failed read leaves all three out rather
          // than showing one of them an older version of the record.
          if (log.trendDays case final days?) ...[
            CycleLengthCard(series: log.series),
            MetricTrendCard(days: days, prefs: log.metricPrefs),
          ],
          const MilestoneNotice(
            title: 'Still to come on this screen',
            body:
                'What runs today is the symptom comparison, the cycle lengths, the '
                'measurements you have switched on, the blood tests you entered '
                'and the self-check ratings. Nothing here shows sample data, and '
                'nothing is projected past the last day you recorded.',
            planned: [
              'A severity distribution that shows how many days were actually good, not just the bad ones.',
              'The same gate applied to sleep and medication adherence, once those are logged long enough.',
            ],
          ),
        ],
        // The lab results are their own read, so they are drawn whether or not the
        // six-month window above loaded. A failed symptom read must not hide a
        // blood test someone typed off a printout — the two have nothing to do
        // with each other, and burying one behind the other's error would be the
        // quiet wrongness this screen is written against.
        LabSection(labs: labs),
        // The self-checks are their own read too — they arrive with the record
        // rather than with the six-month window above, so a failed symptom read
        // must not hide them, the same argument the lab card makes.
        MfgSection(log: log),
      ],
    );
  }
}

/// A read that failed says so. An empty screen and an unreadable record are
/// different facts, and showing the second as the first is the quiet wrongness
/// this app is written against.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

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
      child: Text(
        message,
        style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Text(
        'Reading six months of days…',
        style: TextStyle(color: t.textSecondary, fontSize: 13.5),
      ),
    );
  }
}
