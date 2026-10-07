import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../core/app_state.dart';
import 'login_item.dart';

class DesktopShell with WindowListener {
  DesktopShell._(this.state);
  final AppState state;
  static DesktopShell? _instance;
  tray.TrayIcon? _trayIcon;
  tray.Image? _trayImage;
  bool _trayReady = false;
  bool _updatingLaunchAtLogin = false;

  static Future<void> init(AppState state) async {
    if (!Platform.isMacOS) return;
    _instance ??= DesktopShell._(state);
    await _instance!._init();
  }

  Future<void> _init() async {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(420, 560));
    await windowManager.setTitle('DOT');
    windowManager.addListener(this);
    // Closing must quit unless a fully configured tray can reopen the window.
    await windowManager.setPreventClose(false);
    if (state.settings.menuBarIcon) {
      try {
        final data = await rootBundle.load('assets/icons/dot_tray@2x.png');
        final icon = tray.Image.fromBase64(
          base64Encode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        );
        if (icon == null) {
          throw StateError('DOT-menubalkicoon kon niet worden geladen.');
        }
        _trayImage = icon;
        _trayIcon = tray.TrayIcon.create();
        if (_trayIcon == null) {
          throw StateError('DOT-menubalkicoon kon niet worden aangemaakt.');
        }
        _trayIcon!.icon = icon;
        // The 36px source is displayed at 18 logical points on Retina screens.
        _trayIcon!.iconSize = const Size(18, 18);
        _trayIcon!.isIconTemplate = true;
        _trayIcon!.setTooltip('DOT');
        _trayIcon!.addListener(_onTrayEvent);
        await _updateMenu();
        await windowManager.setPreventClose(true);
        _trayReady = true;
      } catch (e) {
        debugPrint('DOT DesktopShell init failed: $e');
        _trayReady = false;
        _trayIcon?.dispose();
        _trayIcon = null;
        _trayImage?.dispose();
        _trayImage = null;
        await windowManager.setPreventClose(false);
      }
    }
    await _setLaunchAtLogin();
    state.settings.addListener(_setLaunchAtLogin);
  }

  Future<void> _setLaunchAtLogin() async {
    if (_updatingLaunchAtLogin) return;
    _updatingLaunchAtLogin = true;
    try {
      final desired = state.settings.launchAtLogin;
      final supported = await LoginItem.isSupported();
      final success = supported && await LoginItem.setEnabled(desired);
      if (!success && state.settings.launchAtLogin == desired) {
        state.settings.launchAtLogin = !desired;
      }
    } catch (e) {
      debugPrint('DOT LoginItem init failed: $e');
    } finally {
      _updatingLaunchAtLogin = false;
    }
  }

  Future<void> _updateMenu() async {
    final menu = tray.Menu.create();
    if (menu == null) {
      throw StateError('DOT-traymenu kon niet worden aangemaakt.');
    }
    final title = tray.MenuItem.createWithLabelAndType(
      'DOT',
      tray.MenuItemType.normal,
    );
    final open = tray.MenuItem.createWithLabelAndType(
      'Open DOT',
      tray.MenuItemType.normal,
    );
    final share = tray.MenuItem.createWithLabelAndType(
      'Snel delen',
      tray.MenuItemType.normal,
    );
    final quit = tray.MenuItem.createWithLabelAndType(
      'Afsluiten',
      tray.MenuItemType.normal,
    );
    if (title == null || open == null || share == null || quit == null) {
      throw StateError('DOT-traymenu-item kon niet worden aangemaakt.');
    }
    open.addListener((event) {
      if (event is tray.MenuItemClickedEvent) _openWindow();
    });
    share.addListener((event) {
      if (event is tray.MenuItemClickedEvent) _openShareWindow();
    });
    quit.addListener((event) {
      if (event is tray.MenuItemClickedEvent) windowManager.destroy();
    });
    menu
      ..addItem(title)
      ..addSeparator()
      ..addItem(open)
      ..addItem(share)
      ..addSeparator()
      ..addItem(quit);
    _trayIcon!.setContextMenu(menu);
  }

  void _onTrayEvent(tray.TrayIconEvent event) {
    if (event is tray.TrayIconClickedEvent) _openWindow();
  }

  Future<void> _openWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openShareWindow() async {
    await windowManager.setSize(const Size(380, 520));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
  }

  @override
  Future<void> onWindowClose() async {
    if (_trayReady && state.settings.menuBarIcon) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }
}
