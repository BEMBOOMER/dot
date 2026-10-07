import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  final SharedPreferences prefs;
  SettingsStore(this.prefs);

  ThemeMode get themeMode =>
      ThemeMode.values
          .where((mode) => mode.name == prefs.getString('themeMode'))
          .firstOrNull ??
      ThemeMode.system;
  set themeMode(ThemeMode v) =>
      _set(() => prefs.setString('themeMode', v.name));

  bool get reducedMotion => prefs.getBool('reducedMotion') ?? false;
  set reducedMotion(bool v) => _set(() => prefs.setBool('reducedMotion', v));

  bool get notifications => prefs.getBool('notifications') ?? true;
  set notifications(bool v) => _set(() => prefs.setBool('notifications', v));

  bool get autoReconnect => prefs.getBool('autoReconnect') ?? true;
  set autoReconnect(bool v) => _set(() => prefs.setBool('autoReconnect', v));

  bool get launchAtLogin => prefs.getBool('launchAtLogin') ?? false;
  set launchAtLogin(bool v) => _set(() => prefs.setBool('launchAtLogin', v));

  bool get menuBarIcon => prefs.getBool('menuBarIcon') ?? true;
  set menuBarIcon(bool v) => _set(() => prefs.setBool('menuBarIcon', v));

  /// macOS: where received files go. Null = ~/Downloads/DOT.
  String? get downloadDir => prefs.getString('downloadDir');
  set downloadDir(String? v) => _set(
    () => v == null
        ? prefs.remove('downloadDir')
        : prefs.setString('downloadDir', v),
  );

  String? get deviceName => prefs.getString('deviceName');
  set deviceName(String? v) => _set(
    () => v == null
        ? prefs.remove('deviceName')
        : prefs.setString('deviceName', v),
  );

  bool get onboarded => prefs.getBool('onboarded') ?? false;
  set onboarded(bool v) => _set(() => prefs.setBool('onboarded', v));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
