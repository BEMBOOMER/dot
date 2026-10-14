import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/remote_input.dart';
import '../../core/settings_store.dart';
import '../../core/sync_engine.dart';
import '../../core/typing_diff.dart';
import '../../platform/android_remote.dart';
import '../theme/dot_theme.dart';
import '../widgets/dot_widgets.dart';
import '../widgets/remote_trackpad.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  /// Route argument that opens the screen on the keyboard tab.
  static const keyboardTab = 3;

  /// Open instances; the app only routes here when none is open.
  static int openCount = 0;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen>
    with WidgetsBindingObserver {
  late final AndroidRemote _android;
  late SyncEngine _engine;
  int _tab = 0;
  bool _foreground = true;
  bool _routeCurrent = true;
  bool _nativeActive = false;
  bool _readArguments = false;
  final _keyboardFocus = FocusNode(debugLabel: 'remote-keyboard');
  ValueListenable<TextFocus>? _textFocus;
  int _lastField = 0;

  /// The phone keyboard opened because the Mac asked, so close it again when
  /// the Mac's text field loses focus.
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    RemoteScreen.openCount++;
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _android = AndroidRemote(onVolumeKey: (key) => _send(RemoteInput.key(key)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = context.read<SyncEngine>();
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _listenTextFocus();
    if (!_readArguments) {
      _readArguments = true;
      if (ModalRoute.of(context)?.settings.arguments ==
          RemoteScreen.keyboardTab) {
        _tab = RemoteScreen.keyboardTab;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _textFocus?.value.active == true) _openKeyboard();
        });
      }
    }
    _updateNative();
  }

  void _listenTextFocus() {
    final next = _engine.remoteTextFocus;
    if (identical(next, _textFocus)) return;
    _textFocus?.removeListener(_textFocusChanged);
    _textFocus = next..addListener(_textFocusChanged);
    _lastField = next.value.field;
  }

  void _textFocusChanged() {
    final focus = _textFocus!.value;
    final newField = focus.field != _lastField;
    _lastField = focus.field;
    if (!mounted) return;
    if (!focus.active) {
      if (_autoOpened) {
        _autoOpened = false;
        _keyboardFocus.unfocus();
      }
      setState(() {});
      return;
    }
    final settings = context.read<SettingsStore>();
    if (newField && settings.phoneKeyboard && _foreground && _routeCurrent) {
      _select(RemoteScreen.keyboardTab);
      _openKeyboard();
    } else {
      setState(() {});
    }
  }

  void _openKeyboard({bool auto = true}) {
    _autoOpened = auto && (_autoOpened || !_keyboardFocus.hasFocus);
    // After the frame that shows the keyboard tab and enables its field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tab != RemoteScreen.keyboardTab) return;
      _keyboardFocus.requestFocus();
      // The keyboard may be hidden while the field kept focus.
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
    setState(() {});
  }

  void _updateNative() {
    final active = _tab == 1 && _foreground && _routeCurrent;
    if (_nativeActive == active) return;
    _nativeActive = active;
    unawaited(_android.setPresentationActive(active));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    _updateNative();
  }

  bool get _connected =>
      _engine.status == ConnectionStatus.connected ||
      _engine.status == ConnectionStatus.syncing;

  bool get _demo => context.read<AppState?>()?.isDemoMode ?? false;

  bool get _canSend {
    final status = _engine.remoteStatus.value;
    return _foreground &&
        _routeCurrent &&
        !_engine.isHost &&
        _connected &&
        (_demo || (status.available && status.enabled && status.trusted));
  }

  void _send(RemoteInput input) {
    if (input is PointerDrag && !input.down) {
      _engine.sendInput(input);
      return;
    }
    if (mounted && _canSend) _engine.sendInput(input);
  }

  void _press(RemoteInput input) {
    _send(input);
    HapticFeedback.selectionClick();
  }

  void _select(int tab) {
    if (_tab == tab) return;
    if (_tab == RemoteScreen.keyboardTab) {
      _autoOpened = false;
      _keyboardFocus.unfocus();
    }
    setState(() => _tab = tab);
    _updateNative();
  }

  void _settings() {
    final settings = context.read<SettingsStore>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trackpadsnelheid',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Kies wat prettig voelt.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: Slider(
                    min: .5,
                    max: 2.5,
                    divisions: 20,
                    value: settings.trackpadSpeed,
                    label: '${settings.trackpadSpeed.toStringAsFixed(1)}×',
                    semanticFormatterCallback: (v) =>
                        '${v.toStringAsFixed(1)} keer',
                    onChanged: (value) => settings.trackpadSpeed = value,
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('Rustig'), Text('Snel')],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    RemoteScreen.openCount--;
    WidgetsBinding.instance.removeObserver(this);
    _textFocus?.removeListener(_textFocusChanged);
    _keyboardFocus.dispose();
    _android.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _engine = context.watch<SyncEngine>();
    _listenTextFocus();
    final settings = context.watch<SettingsStore>();
    final demo = context.watch<AppState?>()?.isDemoMode ?? false;
    return ValueListenableBuilder<RemoteInputStatus>(
      valueListenable: _engine.remoteStatus,
      builder: (context, status, _) {
        final enabled = _canSend;
        var disabledReason = 'De trackpad is niet actief';
        if (!_connected) {
          disabledReason = 'Verbind met je Mac om de trackpad te gebruiken';
        } else if (!demo && !status.available) {
          disabledReason =
              'Werk DOT op je Mac bij om de bediening te gebruiken';
        } else if (!demo && !status.enabled) {
          disabledReason = 'Bediening op afstand staat uit op je Mac';
        } else if (!demo && !status.trusted) {
          disabledReason = 'Geef DOT op je Mac toegang via Toegankelijkheid';
        }
        final messages = <String>[
          if (!demo && _connected) ...[
            if (!status.available)
              'Werk DOT op je Mac bij om de bediening te gebruiken.',
            if (!status.enabled) 'Bediening op afstand staat uit op je Mac.',
            if (!status.trusted) 'Geef DOT op je Mac toegang: Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid.',
          ],
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bediening'),
            leading: IconButton(
              tooltip: 'Terug',
              icon: const Icon(Icons.arrow_back_rounded),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (_tab == 0)
                IconButton(
                  tooltip: 'Trackpadinstellingen',
                  constraints: const BoxConstraints(
                    minWidth: 56,
                    minHeight: 56,
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _settings,
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(
                      label: demo
                          ? 'Voorbeeldbediening'
                          : _connected
                          ? 'Verbonden met ${_engine.peerName ?? 'je Mac'}'
                          : statusLabel(
                              _engine.status,
                              peerName: _engine.peerName,
                            ),
                      color: _connected
                          ? DotColors.success(context)
                          : DotColors.secondary(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: DotColors.muted(context),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: Row(
                      children: [
                        for (final (index, label) in [
                          'Trackpad',
                          'Presentatie',
                          'Media',
                          'Typen',
                        ].indexed)
                          Expanded(
                            child: Semantics(
                              selected: _tab == index,
                              child: AnimatedContainer(
                                duration: settings.reducedMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                decoration: BoxDecoration(
                                  color: _tab == index
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: TextButton(
                                  onPressed: () => _select(index),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(56, 56),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    foregroundColor: _tab == index
                                        ? Colors.white
                                        : DotColors.secondary(context),
                                  ),
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      sizing: StackFit.expand,
                      children: [
                        Column(
                          children: [
                            Expanded(
                              child: RemoteTrackpad(
                                send: _send,
                                speed: settings.trackpadSpeed,
                                enabled: enabled && _tab == 0,
                                disabledReason: disabledReason,
                                reducedMotion: settings.reducedMotion,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                for (final (label, button) in [
                                  ('Links', RemoteButton.left),
                                  ('Rechts', RemoteButton.right),
                                ]) ...[
                                  if (button == RemoteButton.right)
                                    const SizedBox(width: 12),
                                  Expanded(
                                    child: _ControlButton(
                                      label: label,
                                      enabled: enabled,
                                      onPressed: () =>
                                          _press(RemoteInput.click(button)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        _ScrollableTab(
                          messages: messages,
                          child: _Presentation(
                            enabled: enabled,
                            active: _tab == 1 && _foreground && _routeCurrent,
                            onKey: (key) => _press(RemoteInput.key(key)),
                          ),
                        ),
                        _ScrollableTab(
                          messages: messages,
                          child: _Media(
                            enabled: enabled,
                            onMedia: (media) =>
                                _press(RemoteInput.media(media)),
                          ),
                        ),
                        _Keyboard(
                          messages: messages,
                          enabled: enabled,
                          visible: _tab == RemoteScreen.keyboardTab,
                          focusNode: _keyboardFocus,
                          macFieldActive: _textFocus?.value.active ?? false,
                          send: _send,
                          onEdit: (key) => _press(RemoteInput.edit(key)),
                          onOpen: () => _openKeyboard(auto: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Keeps scrolling within the selected controls tab, with no excess extent
/// when its content fits the available height.
class _ScrollableTab extends StatelessWidget {
  final List<String> messages;
  final Widget child;

  const _ScrollableTab({required this.messages, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (messages.isNotEmpty) ...[
                DotCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, message) in messages.indexed) ...[
                          if (index != 0) const SizedBox(height: 12),
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ControlButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool primary;
  final IconData? icon;
  final bool vertical;

  const _ControlButton({
    required this.label,
    required this.onPressed,
    required this.enabled,
    this.primary = false,
    this.icon,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final contents = [
      if (icon != null) Icon(icon, size: vertical ? 36 : 22),
      if (icon != null)
        SizedBox(width: vertical ? 0 : 8, height: vertical ? 12 : 0),
      Flexible(child: Text(label, textAlign: TextAlign.center)),
    ];
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: primary
            ? Theme.of(context).colorScheme.primary
            : DotColors.muted(context),
        foregroundColor: primary
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
        shape: const StadiumBorder(),
        animationDuration: context.watch<SettingsStore>().reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
      ),
      child: vertical
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: contents,
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: contents,
            ),
    );
  }
}

class _Presentation extends StatefulWidget {
  final bool enabled;
  final bool active;
  final void Function(RemoteKey key) onKey;
  const _Presentation({
    required this.enabled,
    required this.active,
    required this.onKey,
  });
  @override
  State<_Presentation> createState() => _PresentationState();
}

class _PresentationState extends State<_Presentation> {
  final _clock = Stopwatch();
  Timer? _timer;

  void _toggle() {
    setState(() {
      if (_clock.isRunning) {
        _clock.stop();
        _timer?.cancel();
      } else if (widget.active) {
        _clock.start();
        _timer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => setState(() {}),
        );
      }
    });
    HapticFeedback.selectionClick();
  }

  void _reset() {
    _timer?.cancel();
    _clock.stop();
    setState(_clock.reset);
    HapticFeedback.lightImpact();
  }

  @override
  void didUpdateWidget(_Presentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _clock.stop();
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _clock.stop();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _clock.elapsed.inSeconds;
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Semantics(
              button: true,
              label:
                  'Diatimer $time. Tik om te starten of pauzeren. Houd vast om te resetten.',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('slide-timer'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: widget.active ? _toggle : null,
                  onLongPress: _reset,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _clock.isRunning
                                ? 'Tik om te pauzeren'
                                : 'Tik om te starten',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 136,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ControlButton(
                  label: 'Vorige',
                  icon: Icons.chevron_left_rounded,
                  vertical: true,
                  enabled: widget.enabled,
                  onPressed: () => widget.onKey(RemoteKey.prev),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _ControlButton(
                  label: 'Volgende',
                  icon: Icons.chevron_right_rounded,
                  vertical: true,
                  primary: true,
                  enabled: widget.enabled,
                  onPressed: () => widget.onKey(RemoteKey.next),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final row in [
          [
            ('Start', RemoteKey.start),
            ('Keynote starten', RemoteKey.startKeynote),
          ],
          [('Zwart scherm', RemoteKey.blackout), ('Stop', RemoteKey.end)],
        ]) ...[
          Row(
            children: [
              for (final (index, (label, key)) in row.indexed) ...[
                if (index != 0) const SizedBox(width: 12),
                Expanded(
                  child: _ControlButton(
                    label: label,
                    enabled: widget.enabled,
                    onPressed: () => widget.onKey(key),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Media extends StatelessWidget {
  final bool enabled;
  final void Function(RemoteMedia media) onMedia;
  const _Media({required this.enabled, required this.onMedia});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in [
          [
            ('Vorige', Icons.skip_previous_rounded, RemoteMedia.prev),
            (
              'Afspelen of pauzeren',
              Icons.play_arrow_rounded,
              RemoteMedia.playpause,
            ),
            ('Volgende', Icons.skip_next_rounded, RemoteMedia.next),
          ],
          [
            ('Zachter', Icons.volume_down_rounded, RemoteMedia.voldown),
            ('Dempen', Icons.volume_off_rounded, RemoteMedia.mute),
            ('Harder', Icons.volume_up_rounded, RemoteMedia.volup),
          ],
        ]) ...[
          Row(
            children: [
              for (final (label, icon, media) in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 16,
                    ),
                    child: Column(
                      children: [
                        Tooltip(
                          message: label,
                          child: FilledButton(
                            onPressed: enabled ? () => onMedia(media) : null,
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(72, 72),
                              shape: const CircleBorder(),
                              backgroundColor: media == RemoteMedia.playpause
                                  ? Theme.of(context).colorScheme.primary
                                  : DotColors.muted(context),
                              foregroundColor: media == RemoteMedia.playpause
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                              animationDuration:
                                  context.watch<SettingsStore>().reducedMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                            ),
                            child: Icon(
                              icon,
                              size: media == RemoteMedia.playpause ? 40 : 28,
                              semanticLabel: label,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          media == RemoteMedia.playpause
                              ? 'Afspelen/pauze'
                              : label,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// Types on the Mac. The field mirrors what is typed for feedback; each edit
/// is turned into keystrokes by [TypingDiff].
class _Keyboard extends StatefulWidget {
  final List<String> messages;
  final bool enabled;
  final bool visible;
  final bool macFieldActive;
  final FocusNode focusNode;
  final void Function(RemoteInput input) send;
  final void Function(EditKey key) onEdit;
  final VoidCallback onOpen;

  const _Keyboard({
    required this.messages,
    required this.enabled,
    required this.visible,
    required this.macFieldActive,
    required this.focusNode,
    required this.send,
    required this.onEdit,
    required this.onOpen,
  });

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  /// Zero-width space before the cursor, so a backspace in an otherwise empty
  /// field is still visible as an edit and reaches the Mac.
  static const _sentinel = '​';

  /// Start over once the mirror gets long, between words.
  static const _resetLength = 160;

  final _controller = TextEditingController(text: _sentinel);
  String _sent = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_pinCursor);
    widget.focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(_Keyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  /// Every edit must happen at the end, matching the caret on the Mac.
  void _pinCursor() {
    final value = _controller.value;
    final end = value.text.length;
    if (value.composing.isValid) return;
    if (value.selection.isCollapsed && value.selection.baseOffset == end) {
      return;
    }
    _controller.value = value.copyWith(
      selection: TextSelection.collapsed(offset: end),
    );
  }

  void _changed(String text) {
    var backspaces = 0;
    var body = text;
    if (body.startsWith(_sentinel)) {
      body = body.substring(_sentinel.length);
    } else {
      // The sentinel itself was deleted: one backspace on an empty mirror.
      backspaces = 1;
      body = body.replaceAll(_sentinel, '');
    }
    final diff = TypingDiff.between(_sent, body);
    _sent = body;
    if (!widget.enabled) {
      _reset();
      return;
    }
    for (var i = 0; i < backspaces; i++) {
      widget.send(const RemoteInput.edit(EditKey.backspace));
    }
    for (final input in diff.toInputs()) {
      widget.send(input);
    }
    final composing = _controller.value.composing.isValid;
    final endedLine = body.endsWith('\n');
    final mustRestore = backspaces > 0;
    if (mustRestore ||
        endedLine ||
        (!composing && body.length > _resetLength && body.endsWith(' '))) {
      _reset();
    }
  }

  void _reset() {
    _sent = '';
    _controller.value = const TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: _sentinel.length),
    );
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typing = widget.focusNode.hasFocus;
    final status = !widget.enabled
        ? null
        : widget.macFieldActive
        ? 'Tekstveld actief op je Mac'
        : 'Klik op je Mac in een tekstveld';
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final message in widget.messages) ...[
                Text(message, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
              ],
              if (status != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: status,
                    color: widget.macFieldActive
                        ? DotColors.success(context)
                        : DotColors.secondary(context),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              DotCard(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    key: const ValueKey('remote-keyboard-field'),
                    controller: _controller,
                    focusNode: widget.focusNode,
                    enabled: widget.enabled && widget.visible,
                    onChanged: _changed,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    enableInteractiveSelection: false,
                    minLines: 4,
                    maxLines: 6,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      hintText: widget.enabled
                          ? 'Wat je hier typt, verschijnt op je Mac.'
                          : 'Typen is niet actief',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (index, (label, icon, key)) in [
                    ('Wissen', Icons.backspace_outlined, EditKey.backspace),
                    ('Tab', Icons.keyboard_tab_rounded, EditKey.tab),
                    ('Enter', Icons.keyboard_return_rounded, EditKey.enter),
                  ].indexed) ...[
                    if (index != 0) const SizedBox(width: 12),
                    Expanded(
                      child: _ControlButton(
                        label: label,
                        icon: icon,
                        enabled: widget.enabled,
                        onPressed: () => widget.onEdit(key),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (index, (label, icon, key)) in [
                    ('Links', Icons.arrow_back_rounded, EditKey.left),
                    ('Omhoog', Icons.arrow_upward_rounded, EditKey.up),
                    ('Omlaag', Icons.arrow_downward_rounded, EditKey.down),
                    ('Rechts', Icons.arrow_forward_rounded, EditKey.right),
                  ].indexed) ...[
                    if (index != 0) const SizedBox(width: 12),
                    Expanded(
                      child: Tooltip(
                        message: label,
                        child: FilledButton(
                          onPressed: widget.enabled
                              ? () => widget.onEdit(key)
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(56, 56),
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                            backgroundColor: DotColors.muted(context),
                            foregroundColor: theme.colorScheme.onSurface,
                          ),
                          child: Icon(icon, semanticLabel: label),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!typing) ...[
                const SizedBox(height: 16),
                _ControlButton(
                  label: 'Toetsenbord openen',
                  icon: Icons.keyboard_rounded,
                  primary: true,
                  enabled: widget.enabled,
                  onPressed: widget.onOpen,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
