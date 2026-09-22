/// The mFG self-check card: every check as a dated line of separate answers,
/// and no score anywhere.
///
/// The card carries the refusal in its blurb because this is the screen where
/// the feature is discovered, and someone who knows the clinical check will
/// look here for the number first. What they get instead is the shape `B1`
/// asked for (`docs/feature_research.md`): the checks, newest first, each one
/// its own row of the areas that were rated — and where fewer than nine were,
/// the count, so a gap can never be read as an area rated none.
///
/// Removal goes through `writeAndOfferUndo` like every other destructive tap
/// here: the check leaves the list optimistically and one level of undo brings
/// the whole day's check back as it was.
library;

import 'package:flutter/material.dart';

import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import '../log/undo_toast.dart';
import 'mfg_sheet.dart';

class MfgSection extends StatelessWidget {
  const MfgSection({super.key, required this.log});

  final LogController log;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final checks = log.mfgChecks;

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
              Icon(Icons.fact_check_outlined, size: 18, color: t.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hirsutism self-check',
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
            'The nine areas rated 0 to 4 on a day you checked, kept as nine '
            'separate answers over time. This app never adds them into one '
            'number — no total, no threshold.',
            style:
                TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
          ),
          if (checks.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Nothing checked yet. When you have looked at the nine areas, '
              'record it here — dated, and worded the same way in the doctor '
              'report.',
              style:
                  TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.45),
            ),
          ] else
            for (final check in checks.reversed) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${dayLabel(check.day, inYear: log.today.year)} — '
                          '${check.summary}',
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        if (check.partialNote case final note?) ...[
                          const SizedBox(height: 2),
                          Text(
                            note,
                            style: TextStyle(
                              color: t.textFaint,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: log.canWrite
                        ? () => _remove(context, check.day)
                        : null,
                    tooltip: 'Remove this check',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(
                      Icons.close_outlined,
                      size: 18,
                      color: t.textFaint,
                    ),
                  ),
                ],
              ),
            ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: log.canWrite ? () => showMfgSheet(context, log) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Record a check'),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, DateTime day) async {
    await writeAndOfferUndo(context, log, () => log.removeMfgCheck(day));
  }
}
