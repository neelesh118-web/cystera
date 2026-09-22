import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_text.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/theme/app_theme.dart';
import 'settings_sections.dart';

/// The parts of the phone the app can describe, and therefore cannot lie about.
///
/// The report is injectable so this can be rendered in a test without a
/// filesystem: the panel's job is to *say* what the storage layer found, and
/// that is worth testing directly rather than through a scroll.
class StoragePanel extends StatefulWidget {
  const StoragePanel({super.key, this.loadReport});

  /// Null means "ask the controller", which is what the app does. It is a
  /// callback rather than a future so the load starts during the build that will
  /// listen to it — a future prepared earlier can fail before anyone is attached
  /// to it, which in a test is an unhandled error and in production is a silent
  /// one.
  final Future<StorageReport> Function()? loadReport;

  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  // Held rather than rebuilt on every notification: the controller notifies on
  // each message it sets, and re-reading the disk on every keystroke elsewhere in
  // the app would be both slow and misleading.
  late final Future<StorageReport> _report =
      (widget.loadReport ?? context.read<LockController>().storageReport)();

  @override
  Widget build(BuildContext context) {
    final text = AppTextScope.of(context);
    return SettingsSection(
      label: text.storageHeading,
      children: [
        FutureBuilder<StorageReport>(
          future: _report,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Fact(
                label: text.storageCheckTitle,
                value: text.storageUnreadable('${snapshot.error}'),
                warning: true,
              );
            }
            if (!snapshot.hasData) {
              return const ListTile(
                title: SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              );
            }
            final report = snapshot.data!;
            final protection = report.keyProtection;
            return Column(
              children: [
                // First, because it is the sentence the app used to make without
                // checking: where the key that protects everything else actually
                // lives, as the phone describes it rather than as a library version
                // suggests.
                _Fact(
                  label: text.vaultKeyLabel,
                  // Not translated, and deliberately: this is the phone's own answer
                  // about where the key lives, describing hardware by name. A
                  // translation of it would be a claim about a keystore nobody
                  // re-read, and the wrong one is worse than an English one.
                  value: protection.headline,
                  warning: protection.warning,
                  note: protection.detail,
                  footnotes: protection.footnotes,
                ),
                _Fact(
                  label: text.databaseLabel,
                  value: report.database.exists
                      ? text.databaseSize(
                          (report.database.sizeBytes / 1024).toStringAsFixed(0),
                        )
                      : text.databaseNotCreated,
                ),
                _Fact(
                  label: text.databaseKeyLabel,
                  value: report.shape.keyWrappedByPin
                      ? text.keyPinOnly
                      : report.shape.keyStoredUnwrapped
                          ? text.keyKeystore
                          : text.keyMissing,
                  warning: report.shape.keyStoredUnwrapped && report.shape.hasPin,
                ),
                _Fact(
                  label: text.biometricCopyLabel,
                  value: report.shape.keyWrappedForBiometrics
                      ? text.keyPresent
                      : text.keyNone,
                ),
                _Fact(
                  label: text.consistencyLabel,
                  value: report.shape.isConsistent
                      ? text.consistencyPassed
                      : text.consistencyFailed,
                  warning: !report.shape.isConsistent,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.warning = false,
    this.note,
    this.footnotes = const <String>[],
  });

  final String label;
  final String value;
  final bool warning;

  /// What the value means, in the words the fact itself does not have room for.
  final String? note;

  /// What changes how the value should be read.
  final List<String> footnotes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: t.textFaint, fontSize: 12.5)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: warning ? t.accent : t.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: warning ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (note case final note?) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.45),
                  ),
                ],
                for (final footnote in footnotes) ...[
                  const SizedBox(height: 4),
                  Text(
                    footnote,
                    style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
