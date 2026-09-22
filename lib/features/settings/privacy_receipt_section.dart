import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/app_text.dart';
import '../../core/privacy/privacy_receipt.dart';
import '../../core/platform/keystore_probe.dart';
import '../../core/platform/permission_probe.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import 'settings_sections.dart';

/// The privacy receipt: what this phone just answered about its permissions
/// and its keystore, laid out as lines you can read and copy.
///
/// Two things this screen is careful about, and they are the section's whole
/// design:
///
///  * **Generated, not asserted.** Every row is mapped from one [ReceiptLine],
///    which the generator only produces from a query's answer. When a query
///    fails the row says "not read" rather than sliding back into the claims
///    the app used to make from its own manifest — so a platform that cannot
///    answer produces an honest receipt, not a reassuring one.
///  * **The phone's own words stay the phone's own words.** The keystore value
///    is the probe's English description of hardware by name, untranslated for
///    the same reason the storage panel leaves it so: a translation of it would
///    be a claim about a keystore nobody re-read, and the wrong one is worse
///    than an English one.
///
/// The copy button exists because a receipt you cannot take with you is a
/// receipt you have to photograph. It shares the exact rows on screen — the
/// same list, built by the same function, so the copy cannot drift from what
/// was read.
class PrivacyReceiptSection extends StatefulWidget {
  const PrivacyReceiptSection({super.key});

  @override
  State<PrivacyReceiptSection> createState() => _PrivacyReceiptSectionState();
}

class _PrivacyReceiptSectionState extends State<PrivacyReceiptSection> {
  // Asked once, during the build that will listen to it — the storage panel's
  // rule: a future prepared earlier can fail before anyone is attached, which
  // in a test is an unhandled error and in production a silent one.
  late final Future<PrivacyReceipt> _receipt = _read();

  static Future<PrivacyReceipt> _read() async {
    final permissions = await const PlatformPermissionProbe().reading();
    final keystore = await const PlatformKeystoreProbe().report();
    return PrivacyReceipt.generate(
      permissions: permissions,
      keystore: keystore,
    );
  }

  /// The rows as drawn — and, byte for byte, as copied. One function so the
  /// two cannot disagree.
  List<({String label, String value, bool warning})> _rows(
    PrivacyReceipt receipt,
    AppText text,
  ) =>
      [for (final line in receipt.lines) _describe(line, text)];

  ({String label, String value, bool warning}) _describe(
    ReceiptLine line,
    AppText text,
  ) =>
      switch (line.kind) {
        ReceiptKind.network => (
          label: text.privacyNetworkLabel,
          value: switch (line.status) {
            ReceiptStatus.ok => text.privacyNoInternet,
            ReceiptStatus.problem => text.privacyInternetRequested,
            _ => _unread(text, line.value),
          },
          warning: line.status != ReceiptStatus.ok,
        ),
        ReceiptKind.permission => (
          label: _shortName(line.name ?? ''),
          value: line.granted == true
              ? text.privacyGranted
              : line.granted == false
                  ? text.privacyNotGranted
                  : text.privacyNotSaid,
          warning: line.granted == null,
        ),
        ReceiptKind.keystore => (
          label: text.privacyKeystoreLabel,
          value: line.value ?? '',
          warning: line.status == ReceiptStatus.problem ||
              line.status == ReceiptStatus.unread,
        ),
      };

  String _unread(AppText text, String? detail) =>
      detail == null || detail.isEmpty
          ? text.privacyNotRead
          : text.privacyReadError(detail);

  /// `android.permission.POST_NOTIFICATIONS` → `POST_NOTIFICATIONS`: the
  /// prefix is package plumbing the reader did not ask for; the name is the
  /// part the phone distinguishes things by.
  String _shortName(String name) {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(dot + 1);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTextScope.of(context);
    return SettingsSection(
      label: text.receiptHeading,
      footnote: text.receiptFootnote,
      children: [
        FutureBuilder<PrivacyReceipt>(
          future: _receipt,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              // The generator is total, so this is a future that failed rather
              // than a receipt that could not be built — said plainly instead
              // of drawn as a blank card.
              return _Row(
                label: '',
                value: text.privacyReadError('${snapshot.error}'),
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
            final rows = _rows(snapshot.data!, text);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows) ...[
                  _Row(
                    label: row.label,
                    value: row.value,
                    warning: row.warning,
                  ),
                ],
                ListTile(
                  leading: Icon(
                    Icons.copy_all_outlined,
                    size: 20,
                    color: context.tokens.textSecondary,
                  ),
                  title: Text(
                    text.privacyCopyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => _copy(rows, text),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _copy(
    List<({String label, String value, bool warning})> rows,
    AppText text,
  ) async {
    // Captured before the await, along with the wording: the async gap is
    // where a stale context would otherwise be read.
    final messenger = ScaffoldMessenger.of(context);
    final header = text.privacyReceiptHeader(
      dayLabel(DateTime.now()),
    );
    final body = [
      for (final row in rows) '${row.label}: ${row.value}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: '$header\n$body'));
    messenger.showSnackBar(SnackBar(content: Text(text.privacyCopied)));
  }
}

/// One receipt line as a settings row: label, value, and the warning weight
/// when the value is a problem or an absence.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.warning = false});

  final String label;
  final String value;
  final bool warning;

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
            child: Text(
              label,
              style: TextStyle(color: t.textFaint, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: warning ? t.accent : t.textPrimary,
                fontSize: 13,
                height: 1.4,
                fontWeight: warning ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
