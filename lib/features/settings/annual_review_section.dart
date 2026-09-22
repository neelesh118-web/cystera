import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/app_text.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import 'settings_sections.dart';

/// The annual review pack: when the next one is due, and the one-page PDF to
/// take to it.
///
/// Two things this screen is careful about, and they are the section's whole
/// design:
///
///  * **The due date is anchored on a date the user stated, never inferred.**
///    There is no diagnosis date in this record and the app will not mint an
///    anniversary out of the install date. Until a review date is recorded, the
///    line says so and offers the picker — a missing due date stated honestly
///    rather than a plausible one computed silently.
///  * **The gaps are the feature.** The pack's subtitle names the phrase the PDF
///    prints on every line it cannot fill, because a checklist that quietly
///    drops what it cannot answer reads as a checklist that was answered.
///
/// The pack shares through the same temporary-file path as the doctor report —
/// it is the same trade, an unencrypted file built to leave the phone, and the
/// footnote says so in the same words.
class AnnualReviewSection extends StatelessWidget {
  const AnnualReviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final lock = context.watch<LockController>();
    final log = context.watch<LogController>();
    final unlocked = lock.phase == LockPhase.unlocked;

    final due = log.annualReviewDue;
    // Overdue only exists while the record is open — the locked branch above
    // answers first — so this flag can never disagree with the line it styles.
    final overdue = unlocked && due != null && due.isBefore(log.today);
    final String dueSubtitle;
    if (!unlocked) {
      dueSubtitle = text.openRecordFirst;
    } else if (due == null) {
      dueSubtitle = text.annualReviewDueNone;
    } else {
      final when = dayLabel(due, inYear: log.today.year);
      dueSubtitle = overdue
          ? text.annualReviewDueOverdue(when)
          : text.annualReviewDueOn(when);
    }

    return SettingsSection(
      label: text.annualReviewHeading,
      footnote: text.annualReviewFootnote,
      children: [
        ListTile(
          leading: Icon(
            // The check-calendar says "done"; an overdue review is the one
            // thing on this screen asking for attention, and it wears the
            // same accent the reminders panel marks its weak lines with.
            overdue
                ? Icons.warning_amber_outlined
                : Icons.event_available_outlined,
            size: 20,
            color: overdue
                ? t.accent
                : unlocked
                    ? t.textSecondary
                    : t.textFaint,
          ),
          title: Text(
            text.annualReviewDueTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            dueSubtitle,
            style: TextStyle(
              color: overdue ? t.accent : t.textSecondary,
              fontSize: 13,
              height: 1.45,
              // The same weight the receipt gives a warning value: the
              // attention is carried by the line itself, not by a second
              // caption saying that it matters.
              fontWeight: overdue ? FontWeight.w600 : null,
            ),
          ),
          onTap: unlocked ? () => _pickDate(context, log, text) : null,
        ),
        ListTile(
          leading: Icon(
            Icons.assignment_turned_in_outlined,
            size: 20,
            color: unlocked ? context.tokens.textSecondary : context.tokens.textFaint,
          ),
          title: Text(
            text.annualReviewPackTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            unlocked ? text.annualReviewPackDetail : text.openRecordFirst,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          onTap: unlocked ? () => _export(context) : null,
        ),
      ],
    );
  }

  /// Asks when the last review was. Bounded to today because a review that has
  /// not happened yet cannot anchor a due date — and the picker is the only
  /// place the app learns this date at all.
  Future<void> _pickDate(
    BuildContext context,
    LogController log,
    AppText text,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: log.annualReview.lastReviewDay ?? log.today,
      firstDate: DateTime(2000),
      lastDate: log.today,
      helpText: text.annualReviewPickDate,
    );
    if (picked == null) return;
    await log.setAnnualReviewDay(picked);
    if (log.error case final error?) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _export(BuildContext context) async {
    final controller = context.read<LogController>();
    final messenger = ScaffoldMessenger.of(context);
    // Held across the awaits below, like `messenger`: reading the scope again
    // after a share sheet would be reading whatever locale the app has by then.
    final text = AppTextScope.of(context);

    try {
      final pack = await controller.buildAnnualReview();
      if (pack == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(text.reportNothing)),
        );
        return;
      }

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${pack.pdfName}');
      await file.writeAsBytes(pack.pdf, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: 'application/pdf'),
          ],
          subject: text.annualReviewShareTitle,
          text: text.annualReviewShareText,
        ),
      );

      messenger.showSnackBar(
        SnackBar(content: Text(text.annualReviewReady)),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(text.reportFailed('$error'))),
      );
    }
  }
}
