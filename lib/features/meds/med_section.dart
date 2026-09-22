import 'package:flutter/material.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/log_controller.dart';
import '../../core/meds/adherence.dart';
import '../../core/meds/med_models.dart';
import '../../core/theme/app_theme.dart';
import '../log/log_widgets.dart';
import '../log/undo_toast.dart';
import 'med_list_sheet.dart';

/// What was taken today, and what the last month looks like.
///
/// Two taps per medication and no third: taken, or skipped. The absence of a tap is
/// a third *fact* — nothing recorded — and the card says so under the rows rather
/// than in a comment, because it is the difference between this and every adherence
/// screen that counts a day nobody opened the app as a missed dose.
///
/// Nothing here asks the user whether they took it. The app does not nag, does not
/// notify per dose, and does not score the month: it keeps the list, records what
/// was said, and counts it in words.
class MedSection extends StatelessWidget {
  const MedSection({super.key, required this.log});

  final LogController log;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final medications = log.medications;
    final report = log.medAdherenceReport;

    return LogCard(
      title: text.medCardTitle,
      blurb: 'Your list, and what happened today. A daily dose is a yes or a no, '
          'not a severity.',
      icon: Icons.medication_outlined,
      children: [
        if (medications.isEmpty)
          Text(
            'Nothing on your list yet. Add a medication or a supplement and it '
            'will appear here every day.',
            style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.45),
          )
        else
          for (final medication in medications)
            _MedRow(
              medication: medication,
              take: log.takeFor(medication.id),
              enabled: log.canWrite,
              onTap: (take) async {
                await writeAndOfferUndo(
                  context,
                  log,
                  () => log.tapMedTake(medication.id, take),
                );
              },
            ),
        const SizedBox(height: 4),
        // A `Wrap` rather than a `Row` with a `Spacer`: these are two labels that
        // both announce themselves in full, and on a 360pt phone at a slightly
        // enlarged text scale they do not fit side by side. A row would clip the
        // second one — which is how a button that offers the month's counts
        // becomes a button nobody can press. When they fit, they still sit on one
        // line; the spacing is what they get instead of the spacer.
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => showMedListSheet(context, log),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                medications.isEmpty ? text.addOne : text.editList,
              ),
            ),
            if (medications.isNotEmpty && report == null)
              TextButton(
                onPressed: log.medsLoading ? null : log.loadMedWindow,
                child: Text(log.medsLoading ? 'Counting…' : 'Show the last 30 days'),
              ),
          ],
        ),
        if (log.medsError case final error?) ...[
          const SizedBox(height: 6),
          Text(error, style: TextStyle(color: t.accent, fontSize: 12.5, height: 1.4)),
        ],
        if (report case final report?) ...[
          const SizedBox(height: 12),
          _Adherence(report: report),
        ],
        const SizedBox(height: 10),
        Text(
          'A day with nothing tapped is not a missed day, and there is no '
          'percentage here on purpose: the counts are the report.',
          style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

/// One medication: name, dose, and the two taps.
class _MedRow extends StatelessWidget {
  const _MedRow({
    required this.medication,
    required this.take,
    required this.enabled,
    required this.onTap,
  });

  final Medication medication;
  final MedTake? take;
  final bool enabled;
  final void Function(MedTake take) onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  medication.displayName,
                  style: TextStyle(
                    color: enabled ? t.textPrimary : t.textFaint,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // The third state, named where it matters. It is a label rather than
              // an empty gap so nobody has to guess whether they answered.
              Text(
                take == null ? text.notRecorded : take!.meaning,
                style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final option in MedTake.values) ...[
                Expanded(
                  child: _MedTap(
                    label: text.takeWord(option.name, option.word),
                    selected: take == option,
                    enabled: enabled,
                    onTap: () => onTap(option),
                  ),
                ),
                if (option != MedTake.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MedTap extends StatelessWidget {
  const _MedTap({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Skipped is drawn in the neutral surface rather than a warning colour: not
    // taking something is a decision, not a failure, and an app that paints it red
    // is grading the person using it.
    final fill = selected ? t.accent : t.surface;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: selected ? t.accent : t.border, width: 1.3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: !enabled
                  ? t.textFaint
                  : selected
                      ? t.onAccent
                      : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The last thirty days, one line per medication, plus the rules behind the numbers.
class _Adherence extends StatelessWidget {
  const _Adherence({required this.report});

  final MedAdherenceReport report;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: t.border, height: 1),
        const SizedBox(height: 12),
        Text(
          'THE LAST ${AdherenceWindow.reportDays} DAYS',
          style: TextStyle(
            color: t.textFaint,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          report.summary,
          style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.5),
        ),
        for (final line in report.lines) ...[
          const SizedBox(height: 8),
          Text(
            '${line.medication.name} — ${line.sentence}',
            style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.5),
          ),
        ],
        const SizedBox(height: 10),
        for (final note in MedAdherenceReport.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              note,
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ),
      ],
    );
  }
}
