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

  double get trackpadSpeed {
    final value = prefs.getDouble('trackpadSpeed') ?? 1.0;
    return value.isFinite ? value.clamp(0.5, 2.5).toDouble() : 1.0;
  }

  set trackpadSpeed(double v) {
    if (v.isFinite) {
      _set(() => prefs.setDouble('trackpadSpeed', v.clamp(0.5, 2.5)));
    }
  }

  bool get notifications => prefs.getBool('notifications') ?? true;
  set notifications(bool v) => _set(() => prefs.setBool('notifications', v));

  bool get autoReconnect => prefs.getBool('autoReconnect') ?? true;
  set autoReconnect(bool v) => _set(() => prefs.setBool('autoReconnect', v));

  bool get launchAtLogin => prefs.getBool('launchAtLogin') ?? false;
  set launchAtLogin(bool v) => _set(() => prefs.setBool('launchAtLogin', v));

  bool get remoteControl => prefs.getBool('remoteControl') ?? true;
  set remoteControl(bool v) => _set(() => prefs.setBool('remoteControl', v));

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
