import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../core/app_state.dart';

class DesktopShell with WindowListener {
  DesktopShell._(this.state);
  final AppState state;
  static DesktopShell? _instance;
  tray.TrayIcon? _trayIcon;

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
    if (state.settings.menuBarIcon) {
      _trayIcon = tray.TrayIcon.create();
      if (_trayIcon == null) {
        throw StateError('DOT-menubalkicoon kon niet worden aangemaakt.');
      }
      final icon = tray.Image.fromFile('assets/icons/dot_tray_template.svg');
      if (icon == null) {
        throw StateError('DOT-menubalkicoon kon niet worden geladen.');
      }
      _trayIcon!.icon = icon;
      _trayIcon!.isIconTemplate = true;
      _trayIcon!.setTooltip('DOT');
      _trayIcon!.addListener(_onTrayEvent);
      await _updateMenu();
    }
    launchAtStartup.setup(
      appName: 'DOT',
      appPath: Platform.resolvedExecutable,
    );
    await _setLaunchAtLogin();
    state.settings.addListener(_setLaunchAtLogin);
  }

  Future<void> _setLaunchAtLogin() async {
    if (state.settings.launchAtLogin) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
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
    if (state.settings.menuBarIcon) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }
}
