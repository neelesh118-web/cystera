import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/app_text.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import 'settings_sections.dart';

/// The one part of the app built to leave the phone.
///
/// Everything else in Cystera is designed so nothing gets out; this section is the
/// deliberate exception, and it is written to make that obvious. The report is not
/// encrypted — a doctor has to be able to open it — so the copy says so plainly,
/// and the sharing sheet is the moment the user chooses where it goes.
class ReportSection extends StatelessWidget {
  const ReportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LockController>();
    final unlocked = controller.phase == LockPhase.unlocked;
    final text = AppTextScope.of(context);

    return SettingsSection(
      label: text.reportHeading,
      footnote: text.reportFootnote,
      children: [
        ListTile(
          leading: Icon(
            Icons.description_outlined,
            size: 20,
            color: unlocked ? context.tokens.textSecondary : context.tokens.textFaint,
          ),
          title: Text(
            text.reportPdfTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            unlocked ? text.reportPdfDetail : text.openRecordFirst,
            style: TextStyle(
              color: context.tokens.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          onTap: unlocked ? () => _export(context, pdf: true) : null,
        ),
        ListTile(
          leading: Icon(
            Icons.table_chart_outlined,
            size: 20,
            color: unlocked ? context.tokens.textSecondary : context.tokens.textFaint,
          ),
          title: Text(
            text.csvTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            text.csvDetail,
            style: TextStyle(
              color: context.tokens.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          onTap: unlocked ? () => _export(context, pdf: false) : null,
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, {required bool pdf}) async {
    final controller = context.read<LogController>();
    final messenger = ScaffoldMessenger.of(context);
    // Held across the awaits below, like `messenger`: reading the scope again after
    // a share sheet would be reading whatever locale the app has by then.
    final text = AppTextScope.of(context);

    try {
      final report = await controller.buildReport();
      if (report == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(text.reportNothing)),
        );
        return;
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/${pdf ? report.pdfName : report.csvName}',
      );
      if (pdf) {
        await file.writeAsBytes(report.pdf, flush: true);
      } else {
        await file.writeAsString(report.csv, flush: true);
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: pdf ? 'application/pdf' : 'text/csv',
            ),
          ],
          subject: pdf ? text.reportShareTitle : text.csvShareTitle,
          text: pdf ? text.reportShareText : text.csvShareText,
        ),
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            report.dayCount == 0
                ? text.reportEmpty
                : text.reportReady(report.dayCount, report.monthCount),
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(text.reportFailed('$error'))),
      );
    }
  }
}
