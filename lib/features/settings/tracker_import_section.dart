import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_text.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import 'settings_sections.dart';
import 'tracker_import_sheet.dart';

/// The way in for someone leaving another tracker: one row, gated on an open
/// record, that opens the paste-and-review sheet.
///
/// It sits with Backup rather than the log screen on purpose — this is about
/// moving a record in, not about a day — and the subtitle names the contract
/// before the sheet is even open: every line is checked, and nothing enters the
/// record unticked. That sentence is the feature; the sheet merely keeps it.
class TrackerImportSection extends StatelessWidget {
  const TrackerImportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final lock = context.watch<LockController>();
    final log = context.watch<LogController>();
    final unlocked = lock.phase == LockPhase.unlocked;

    return SettingsSection(
      label: text.importHeading,
      footnote: text.importFootnote,
      children: [
        ListTile(
          leading: Icon(
            Icons.input,
            size: 20,
            color: unlocked ? t.textSecondary : t.textFaint,
          ),
          title: Text(
            text.importTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            unlocked ? text.importDetail : text.openRecordFirst,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          onTap: unlocked ? () => showTrackerImportSheet(context, log) : null,
        ),
      ],
    );
  }
}
