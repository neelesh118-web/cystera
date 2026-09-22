import 'package:flutter/services.dart';

/// The two launcher entries in the manifest.
///
/// Android allows one app to publish more than one launcher icon through
/// `activity-alias`, and only the enabled one is shown. Switching them is how
/// the app can appear as something neutral without being a second app.
class LauncherAliases {
  LauncherAliases._();

  static const String defaultAlias = 'com.onekit.cystera.LauncherDefault';
  static const String discreetAlias = 'com.onekit.cystera.LauncherDiscreet';
}

/// Platform settings that have privacy consequences and therefore need to be
/// testable and visible rather than buried in a Kotlin file.
abstract interface class DevicePrivacyPort {
  /// True when the discreet launcher entry is the one enabled.
  Future<bool> isDiscreet();

  /// Enables one launcher entry and disables the other.
  ///
  /// Android applies this without killing the app, but the launcher may take a
  /// few seconds to redraw, and some launchers only pick it up on their next
  /// refresh. The UI says so instead of pretending it is instant.
  Future<void> setDiscreet(bool discreet);

  /// Turns `FLAG_SECURE` on or off.
  ///
  /// On: screenshots are refused, screen recording shows a blank window, and the
  /// app's card in the recents switcher is blanked rather than showing the last
  /// screen. That last part is why it is on by default — a cycle chart visible
  /// over someone's shoulder on the bus is the cost of leaving it off.
  Future<void> setScreenSecure(bool secure);
}

class PlatformDevicePrivacy implements DevicePrivacyPort {
  const PlatformDevicePrivacy();

  static const MethodChannel _channel =
      MethodChannel('com.onekit.cystera/device');

  @override
  Future<bool> isDiscreet() async =>
      await _channel.invokeMethod<bool>('isDiscreet') ?? false;

  @override
  Future<void> setDiscreet(bool discreet) =>
      _channel.invokeMethod<void>('setDiscreet', {'discreet': discreet});

  @override
  Future<void> setScreenSecure(bool secure) =>
      _channel.invokeMethod<void>('setScreenSecure', {'secure': secure});
}

/// Records what the app asked the platform for. Tests only.
class FakeDevicePrivacy implements DevicePrivacyPort {
  FakeDevicePrivacy({bool discreet = false, bool secure = true})
      : _discreet = discreet,
        _secure = secure;

  bool _discreet;
  bool _secure;

  /// Set to make the platform calls fail, which is what happens on a platform
  /// that has no such channel (a test host, or a future non-Android build).
  bool failEverything = false;

  bool get screenSecure => _secure;

  bool get discreet => _discreet;

  @override
  Future<bool> isDiscreet() async => _discreet;

  @override
  Future<void> setDiscreet(bool discreet) async {
    if (failEverything) throw MissingPluginException('no channel');
    _discreet = discreet;
  }

  @override
  Future<void> setScreenSecure(bool secure) async {
    if (failEverything) throw MissingPluginException('no channel');
    _secure = secure;
  }
}
