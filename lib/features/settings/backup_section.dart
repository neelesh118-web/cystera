import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_payload.dart';
import '../../core/backup/backup_service.dart';
import '../../core/crypto/sealed_box.dart';
import '../../core/i18n/app_text.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/theme/app_theme.dart';
import 'settings_sections.dart';

/// Export, import, and the sentence that matters: what the passphrase is for.
///
/// The file carries the database key as well as the data, so it is exactly as
/// sensitive as the record and has no attempt limit protecting it. Every piece of
/// copy here is written with that in mind.
class BackupSection extends StatelessWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LockController>();
    final usable = controller.phase == LockPhase.unlocked;
    final text = AppTextScope.of(context);

    return SettingsSection(
      label: text.backupHeading,
      footnote: text.backupIntro,
      children: [
        ListTile(
          leading: Icon(
            Icons.ios_share,
            size: 20,
            color: usable ? context.tokens.textSecondary : context.tokens.textFaint,
          ),
          title: Text(text.backupMakeTitle, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            usable ? text.backupMakeDetail : text.openRecordFirst,
            style: TextStyle(color: context.tokens.textSecondary, fontSize: 13, height: 1.45),
          ),
          onTap: usable ? () => _export(context) : null,
        ),
        ListTile(
          leading: Icon(
            Icons.restore,
            size: 20,
            color: usable ? context.tokens.textSecondary : context.tokens.textFaint,
          ),
          title: Text(text.restoreTitle, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            text.restoreDetail,
            style: TextStyle(color: context.tokens.textSecondary, fontSize: 13, height: 1.45),
          ),
          onTap: usable ? () => _import(context) : null,
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final controller = context.read<LockController>();
    final messenger = ScaffoldMessenger.of(context);
    final text = AppTextScope.of(context);
    final passphrase = await _askPassphrase(context, confirm: true);
    if (passphrase == null || !context.mounted) return;

    try {
      late final BackupExport export;
      await _runWhileSealing(
        context,
        text.sealingProgress,
        () async {
          export = await controller.exportBackup(
            passphrase: passphrase,
            directory: await getTemporaryDirectory(),
          );
        },
      );

      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(export.file.path, mimeType: 'application/octet-stream')],
          subject: text.backupShareTitle,
          text: text.backupShareText,
        ),
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            text.backupReady((export.bytes / 1024).toStringAsFixed(0)),
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(text.backupFailed('$error'))),
      );
    }
  }

  Future<void> _import(BuildContext context) async {
    final controller = context.read<LockController>();
    final messenger = ScaffoldMessenger.of(context);
    final text = AppTextScope.of(context);

    // file_picker 13 exposes a static API and returns the selection directly.
    final picked = await FilePicker.pickFiles(
      dialogTitle: text.restorePickerTitle,
      type: FileType.any,
    );
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    final file = File(path);

    // Check the file before asking for a passphrase, so "wrong file" and "wrong
    // passphrase" are two different messages.
    try {
      await controller.describeBackupFile(file);
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(text.notABackup)),
      );
      return;
    }

    if (!context.mounted) return;
    final passphrase = await _askPassphrase(context, confirm: false);
    if (passphrase == null) return;

    if (!context.mounted) return;
    final confirmed = await confirmDestructive(
      context,
      title: text.restoreConfirmTitle,
      body: text.restoreConfirmBody,
      confirmLabel: text.replaceLabel,
    );
    if (!confirmed) return;

    try {
      if (!context.mounted) return;
      late final RestoreReport report;
      await _runWhileSealing(
        context,
        text.openingProgress,
        () async {
          report = await controller.restoreBackup(file: file, passphrase: passphrase);
        },
      );
      if (!context.mounted) return;
      final age = report.ageFrom(DateTime.now());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            text.restoreDone(
              age,
              (report.databaseBytes / 1024).toStringAsFixed(0),
            ),
          ),
        ),
      );
    } on BadSecretException {
      messenger.showSnackBar(
        SnackBar(content: Text(text.wrongPassphrase)),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(text.restoreFailed('$error'))),
      );
    }
  }

  Future<String?> _askPassphrase(BuildContext context, {required bool confirm}) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _PassphraseDialog(confirm: confirm),
    );
  }

  /// Runs [work] behind a spinner.
  ///
  /// The sealing step takes seconds by design (see `docs/crypto.md` for the
  /// measurement), and a screen that appears frozen for four seconds is how people
  /// decide an app has crashed and force-close it mid-write.
  Future<void> _runWhileSealing(
    BuildContext context,
    String message,
    Future<void> Function() work,
  ) async {
    var dialogOpen = true;
    final navigator = Navigator.of(context, rootNavigator: true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: context.tokens.textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).then((_) => dialogOpen = false),
    );

    try {
      await work();
    } finally {
      if (dialogOpen && navigator.canPop()) navigator.pop();
    }
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.confirm});

  /// True when the user is choosing a new passphrase (and must repeat it).
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final strength = widget.confirm ? BackupPolicy.describe(_first.text) : null;
    final problem = widget.confirm ? BackupPolicy.validatePassphrase(_first.text) : null;

    return AlertDialog(
      title: Text(
        widget.confirm ? text.choosePassphraseTitle : text.enterPassphraseTitle,
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.confirm ? text.passphraseIntro : text.passphraseRestoreHint,
                style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _first,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: text.passphraseLabel,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _second,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: text.againLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text(
                  _problem ?? strength ?? '',
                  style: TextStyle(
                    color: _problem != null ? t.accent : t.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(text.cancel),
        ),
        FilledButton(
          onPressed: _canSubmit(problem) ? _submit : null,
          child: Text(widget.confirm ? text.createFileLabel : text.openLabel),
        ),
      ],
    );
  }

  bool _canSubmit(String? problem) {
    if (!widget.confirm) return _first.text.isNotEmpty;
    return problem == null && _second.text == _first.text;
  }

  void _submit() => Navigator.of(context).pop(_first.text);
}
