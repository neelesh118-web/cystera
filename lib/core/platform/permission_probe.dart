import 'package:flutter/services.dart';

/// What the installed package asks the system for, and what the phone granted.
///
/// Asked of PackageManager through the device channel rather than read from the
/// manifest in the repository, because the *merged* manifest is what actually
/// ships: a permission slipped into the build by a dependency during the merge
/// appears in this answer, and would never appear in a file nobody re-reads.
/// That difference is the whole point — a receipt that recites the repository
/// is a receipt that can silently drift from the binary.
///
/// Total, like every probe here: the phone may not answer (a host test, a build
/// without the channel), and "did not answer" must stay distinguishable from
/// "answered and holds nothing".
class PermissionReading {
  const PermissionReading({
    required this.answered,
    this.requested = const [],
    this.granted = const {},
    this.error,
  });

  /// False when the query itself failed. Permissions being absent while this is
  /// true means the package requests none — a different fact, and the one the
  /// receipt's network line rests on.
  final bool answered;

  /// Every permission string the platform reported, in PackageManager order,
  /// exactly as the platform spells it (`android.permission.POST_NOTIFICATIONS`).
  final List<String> requested;

  /// Name → granted, for the permissions the platform reported flags for. A
  /// name in [requested] but not here means the phone listed it without a flag:
  /// [ReceiptLine.granted] stays null there rather than guessing false.
  final Map<String, bool> granted;

  /// Why it did not answer — the platform's own message, or null when the
  /// failure gave none, which is what tells "no implementation here" apart from
  /// "the package manager threw".
  final String? error;

  /// Total parse: a null map is "no answer", an `error` map is a failed query,
  /// anything else is the permissions themselves. Never throws — a receipt that
  /// crashes is a receipt nobody can read.
  factory PermissionReading.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const PermissionReading(answered: false);
    }
    if (map['error'] case final String error) {
      return PermissionReading(answered: false, error: error);
    }
    final raw = map['permissions'];
    final requested = <String>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is String) requested.add(entry);
      }
    }
    final rawGranted = map['granted'];
    final granted = <String, bool>{};
    if (rawGranted is Map) {
      for (final entry in rawGranted.entries) {
        if (entry.key is String && entry.value is bool) {
          granted[entry.key as String] = entry.value as bool;
        }
      }
    }
    return PermissionReading(
      answered: true,
      requested: requested,
      granted: granted,
    );
  }
}

/// How the app asks the phone what the installed package requests.
abstract interface class PermissionProbe {
  /// Never throws: a platform without this channel answers "not answered".
  Future<PermissionReading> reading();
}

class PlatformPermissionProbe implements PermissionProbe {
  const PlatformPermissionProbe();

  /// The same channel the keystore report and the launcher entry use — one
  /// channel, because one `MainActivity` owns all of it.
  static const MethodChannel _channel =
      MethodChannel('com.onekit.cystera/device');

  @override
  Future<PermissionReading> reading() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'requestedPermissions',
      );
      return PermissionReading.fromMap(map);
    } on MissingPluginException catch (error) {
      return PermissionReading(answered: false, error: error.toString());
    } on PlatformException catch (error) {
      return PermissionReading(answered: false, error: error.toString());
    }
  }
}

/// A probe whose answer the test decides — a host knows nothing about an
/// installed package, and pretending otherwise is how a receipt starts lying.
class FakePermissionProbe implements PermissionProbe {
  FakePermissionProbe(this._reading);

  PermissionReading _reading;

  set readingTo(PermissionReading value) => _reading = value;

  @override
  Future<PermissionReading> reading() async => _reading;
}
