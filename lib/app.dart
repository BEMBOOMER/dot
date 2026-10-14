import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/device_store.dart';
import 'core/item_repository.dart';
import 'core/models.dart';
import 'core/remote_input.dart';
import 'core/settings_store.dart';
import 'core/sync_engine.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/screens/pair_screen.dart';
import 'ui/screens/workspace_screen.dart';
import 'ui/screens/item_detail_screen.dart';
import 'ui/screens/devices_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/remote_screen.dart';
import 'ui/theme/dot_theme.dart';

class DotApp extends StatefulWidget {
  final AppState state;
  const DotApp({super.key, required this.state});
  @override
  State<DotApp> createState() => _DotAppState();
}

class _DotAppState extends State<DotApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      widget.state.engine.onAppLifecycle(
        // Focus loss and permission dialogs do not background networking.
        active:
            state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: widget.state),
        ChangeNotifierProvider<ItemRepository>.value(
          value: widget.state.repository,
        ),
        ChangeNotifierProvider<DeviceStore>.value(value: widget.state.devices),
        ChangeNotifierProvider<SettingsStore>.value(
          value: widget.state.settings,
        ),
        ChangeNotifierProvider<SyncEngine>.value(value: widget.state.engine),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, settings, _) => MaterialApp(
          navigatorKey: _navigator,
          builder: (context, child) => _KeyboardRouter(
            navigator: _navigator,
            child: child ?? const SizedBox.shrink(),
          ),
          title: 'DOT',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: settings.themeMode,
          initialRoute: settings.onboarded ? '/workspace' : '/welcome',
          routes: {
            '/welcome': (_) => const WelcomeScreen(),
            '/pair': (_) => const PairScreen(),
            '/workspace': (_) => const WorkspaceScreen(),
            '/item': (_) => const ItemDetailScreen(),
            '/devices': (_) => const DevicesScreen(),
            '/settings': (_) => const SettingsScreen(),
            '/remote': (_) => const RemoteScreen(),
          },
        ),
      ),
    ),
  );
}

/// Android: opens the keyboard tab when a text field on the Mac gets focus,
/// so the phone keyboard appears without first opening Bediening.
class _KeyboardRouter extends StatefulWidget {
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  const _KeyboardRouter({required this.navigator, required this.child});

  @override
  State<_KeyboardRouter> createState() => _KeyboardRouterState();
}

class _KeyboardRouterState extends State<_KeyboardRouter> {
  ValueListenable<TextFocus>? _focus;
  int _lastField = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.watch<SyncEngine>().remoteTextFocus;
    if (identical(next, _focus)) return;
    _focus?.removeListener(_changed);
    _focus = next..addListener(_changed);
    _lastField = next.value.field;
  }

  void _changed() {
    final focus = _focus!.value;
    final newField = focus.field != _lastField;
    _lastField = focus.field;
    if (!mounted || !focus.active || !newField) return;
    final engine = context.read<SyncEngine>();
    final settings = context.read<SettingsStore>();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (defaultTargetPlatform != TargetPlatform.android ||
        engine.isHost ||
        !settings.phoneKeyboard ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        RemoteScreen.openCount > 0 ||
        (engine.status != ConnectionStatus.connected &&
            engine.status != ConnectionStatus.syncing)) {
      return;
    }
    widget.navigator.currentState?.pushNamed(
      '/remote',
      arguments: RemoteScreen.keyboardTab,
    );
  }

  @override
  void dispose() {
    _focus?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
