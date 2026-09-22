/// The privacy receipt: lines generated from queries, never asserted from
/// beliefs.
///
/// ## The rule this file exists to keep
///
/// A privacy claim is easy to write and hard to check, and the failure mode is
/// comfortable: a sentence saying "no internet permission" that a dependency's
/// merged manifest quietly disproves. So the receipt has one structural
/// guarantee — **every line is a pure function of an answer the phone gave**:
///
///  * The network line is `ok` only when PackageManager did not list the
///    internet permission, and `problem` when it did. The receipt prints what
///    it finds, including bad news, because a receipt that only prints good
///    news is an advertisement.
///  * Permission lines are the platform's own strings in the platform's own
///    order, with the granted flag the platform reported — `null` when it
///    reported none, never a guessed `false`.
///  * The keystore line is the probe's description of the key as the platform
///    described it, and its status is the vault's weakest entry, from
///    `KeystoreReport`.
///  * When a query fails, its lines are `unread` with the platform's own error
///    as the value. Unread is not okay: there is no input to this generator
///    that produces a reassurance without a reading behind it.
///
/// The sentences a person reads live in `AppText` (the settings tile layer);
/// this file produces structure only, so the mapping from query to line is
/// testable without a widget and the wording is translatable without touching
/// the logic.
///
/// Pure: no Flutter widgets, no database, no clock.
library;

import '../platform/keystore_probe.dart';
import '../platform/permission_probe.dart';

/// Which part of the phone's answer a line reports.
enum ReceiptKind {
  /// The internet permission: the one whose absence the app has always
  /// claimed, now read rather than recited.
  network,

  /// One other requested permission, as PackageManager spelled it.
  permission,

  /// What the keystore holds for this app, and how well it is protected.
  keystore,
}

/// What the query said — about the thing, and about whether it could ask.
enum ReceiptStatus {
  /// Read, and the state is what the app would hope for.
  ok,

  /// Read, and the state contradicts what the app's own notes promise. Printed
  /// anyway: this is the line that makes the receipt worth trusting.
  problem,

  /// Read, but there is nothing there to grade — no vault key yet, say. An
  /// empty shelf is information, not a failure.
  info,

  /// Not read. The value carries the platform's own reason when it gave one.
  unread,
}

/// One line of the receipt.
class ReceiptLine {
  const ReceiptLine({
    required this.kind,
    required this.status,
    this.name,
    this.value,
    this.granted,
  });

  final ReceiptKind kind;
  final ReceiptStatus status;

  /// For [ReceiptKind.permission]: the permission exactly as the platform
  /// spelled it. Null for the other kinds.
  final String? name;

  /// For [ReceiptKind.permission]: the platform's granted flag, tri-state.
  /// Null means the phone listed the permission without saying — rendered as
  /// "the phone did not say", never folded into "not granted".
  final bool? granted;

  /// For [ReceiptKind.keystore]: the probe's own description of the vault key,
  /// hardware names and all. For [ReceiptStatus.unread]: the platform's reason.
  final String? value;
}

/// The receipt: every line, in reading order — network first, the permissions
/// PackageManager listed, the keystore last.
class PrivacyReceipt {
  const PrivacyReceipt(this.lines);

  /// The permission the app's manifest notes promise is absent. Compared
  /// against the platform's own strings, so a merged-in INTERNET permission
  /// turns the network line [ReceiptStatus.problem] instead of vanishing.
  static const String internetPermission = 'android.permission.INTERNET';

  final List<ReceiptLine> lines;

  /// Builds the receipt from two readings. Total by construction: every branch
  /// produces lines, and no branch produces a claim without a reading behind
  /// it — the property `test/privacy_receipt_test.dart` holds it to.
  factory PrivacyReceipt.generate({
    required PermissionReading permissions,
    required KeystoreReport? keystore,
  }) {
    final lines = <ReceiptLine>[];

    if (!permissions.answered) {
      lines.add(ReceiptLine(
        kind: ReceiptKind.network,
        status: ReceiptStatus.unread,
        value: permissions.error,
      ));
    } else if (permissions.requested.contains(internetPermission)) {
      lines.add(const ReceiptLine(
        kind: ReceiptKind.network,
        status: ReceiptStatus.problem,
      ));
    } else {
      lines.add(const ReceiptLine(
        kind: ReceiptKind.network,
        status: ReceiptStatus.ok,
      ));
    }

    // The internet permission already has the network line above; listing it
    // twice would read as two facts when it is one.
    if (permissions.answered) {
      for (final name in permissions.requested) {
        if (name == internetPermission) continue;
        final granted = permissions.granted[name];
        lines.add(ReceiptLine(
          kind: ReceiptKind.permission,
          status: granted == null ? ReceiptStatus.unread : ReceiptStatus.ok,
          name: name,
          granted: granted,
        ));
      }
    }

    lines.add(_keystoreLine(keystore));
    return PrivacyReceipt(lines);
  }

  /// The keystore's line, from the probe's answer alone.
  ///
  /// The unread headlines reuse [VaultKeyProtection]'s existing sentences —
  /// `hasRecord` and `pinWrapped` are ignored on those two branches (the
  /// function short-circuits before it reads them), and the receipt
  /// deliberately does not consult the database: it reports what the *phone*
  /// answers, not what the record holds.
  static ReceiptLine _keystoreLine(KeystoreReport? report) {
    if (report == null) {
      return ReceiptLine(
        kind: ReceiptKind.keystore,
        status: ReceiptStatus.unread,
        value: VaultKeyProtection.forReport(
          null,
          hasRecord: true,
          pinWrapped: false,
        ).headline,
      );
    }
    if (report.error != null) {
      return ReceiptLine(
        kind: ReceiptKind.keystore,
        status: ReceiptStatus.unread,
        value: VaultKeyProtection.forReport(
          report,
          hasRecord: true,
          pinWrapped: false,
        ).headline,
      );
    }
    final summary = report.vaultSummary;
    if (report.vaultKeys.isEmpty) {
      // Nothing stored yet: an empty shelf, said as such.
      return ReceiptLine(
        kind: ReceiptKind.keystore,
        status: ReceiptStatus.info,
        value: summary,
      );
    }
    return ReceiptLine(
      kind: ReceiptKind.keystore,
      status: report.allVaultKeysHardwareBacked
          ? ReceiptStatus.ok
          : ReceiptStatus.problem,
      value: summary,
    );
  }
}
