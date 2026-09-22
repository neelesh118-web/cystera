import 'package:flutter/material.dart';

import '../i18n/locale_resolution.dart';
import '../secure/secure_store.dart';

/// Holds the few settings the shell needs.
///
/// The theme is still session-only, and that is deliberate rather than unfinished:
/// milestone 1 exists to prove the shell and the build invariants, and nothing has
/// needed it to survive a relaunch yet. The language does, and the reason it is here
/// rather than with the other preferences is the interesting part.
class SettingsController extends ChangeNotifier {
  SettingsController({SecureStore? store}) : _store = store;

  /// Where the language goes. Null in a test, which is why every read tolerates a
  /// store that is not there.
  final SecureStore? _store;

  /// The key in the secure store. Named with a prefix so it cannot collide with the
  /// vault's own key material, which shares this store.
  static const String localeKey = 'app.locale';

  ThemeMode _themeMode = ThemeMode.system;
  String? _localeCode;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

  /// Null means *follow the device*, which is not the same as English. A phone set
  /// to Kannada with no stored choice should open in Kannada, and only an explicit
  /// pick that differs from the device needs storing at all.
  String? get localeCode => _localeCode;

  /// The locale handed to `MaterialApp`, or null to let Flutter resolve it.
  Locale? get locale => _localeCode == null ? null : localeForCode(_localeCode);

  /// True once the stored choice has been read, so the first frame does not flash
  /// English before a stored language arrives.
  bool get loaded => _loaded;

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
  }

  /// Reads the stored language.
  ///
  /// **Not** in the encrypted record, and that is the decision worth recording here.
  /// Every other preference — cycle mode, contraception, which measurements are on —
  /// lives inside the record so it travels in a backup and cannot be read without the
  /// key. The language cannot: the lock screen, the PIN prompt and the restore screen
  /// all need words *before* the key exists, so a preference the vault guards is a
  /// preference that cannot be used where it is most needed. It is a language code
  /// and nothing else, and it is the only thing the app reads while locked.
  Future<void> load() async {
    _loaded = true;
    final stored = await _store?.read(localeKey);
    if (stored != null && stored != _localeCode) {
      _localeCode = stored;
      notifyListeners();
    }
  }

  /// Passing null clears the choice back to *follow the device*, which is an
  /// instruction rather than a missing value — hence a delete rather than a write of
  /// something that looks like English.
  Future<void> setLocaleCode(String? code) async {
    if (code == _localeCode) return;
    _localeCode = code;
    notifyListeners();
    if (code == null) {
      await _store?.delete(localeKey);
    } else {
      await _store?.write(localeKey, code);
    }
  }
}
