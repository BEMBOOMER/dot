import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/remote_input.dart';
import '../theme/dot_theme.dart';

/// Raw contacts share one gesture session, including staggered finger lifts.
/// Motion is accumulated here and sent only on display frames, capped at 120 Hz.
class RemoteTrackpad extends StatefulWidget {
  final void Function(RemoteInput input) send;
  final double speed;
  final bool enabled;
  final bool reducedMotion;

  const RemoteTrackpad({
    super.key,
    required this.send,
    required this.speed,
    required this.enabled,
    required this.reducedMotion,
  });

  @override
  State<RemoteTrackpad> createState() => _RemoteTrackpadState();
}

class _Contact {
  Offset position;
  final Offset start;
  Duration timestamp;
  _Contact(this.position, this.timestamp) : start = position;
}

class _RemoteTrackpadState extends State<RemoteTrackpad> {
  static const _slop = 6.0;
  static const _doubleTapWindow = Duration(milliseconds: 240);
  final _contacts = <int, _Contact>{};
  Timer? _holdTimer;
  Timer? _tapTimer;
  Offset? _lastTap;
  Offset _move = Offset.zero;
  Offset _scroll = Offset.zero;
  Offset _uncommitted = Offset.zero;
  double _velocity = 0;
  int _maxContacts = 0;
  int? _frame;
  Duration? _lastFrame;
  Duration _started = Duration.zero;
  Offset _start = Offset.zero;
  bool _moved = false;
  bool _cancelled = false;
  bool _dragging = false;
  bool _releasePending = false;
  bool _touched = false;

  @override
  void didUpdateWidget(RemoteTrackpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _reset();
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (!_touched) setState(() => _touched = true);
    if (_contacts.isEmpty) {
      _finishDrag();
      _started = event.timeStamp;
      _start = event.localPosition;
      _maxContacts = 0;
      _moved = false;
      _cancelled = false;
      _velocity = 0;
      _uncommitted = Offset.zero;
    }
    _contacts[event.pointer] = _Contact(event.localPosition, event.timeStamp);
    _maxContacts = math.max(_maxContacts, _contacts.length);
    _holdTimer?.cancel();
    if (_contacts.length == 1 && _maxContacts == 1) {
      _holdTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || !widget.enabled || _moved || _contacts.length != 1) {
          return;
        }
        _commitTap();
        _dragging = true;
        widget.send(const RemoteInput.drag(down: true));
        HapticFeedback.lightImpact();
      });
    } else {
      _commitTap();
      _move = Offset.zero;
      _uncommitted = Offset.zero;
      if (_dragging) _finishDrag();
      if (_contacts.length > 2) _cancelled = true;
    }
  }

  void _motion(PointerMoveEvent event) {
    final contact = _contacts[event.pointer];
    if (!widget.enabled || contact == null || _cancelled) return;
    final delta = event.localPosition - contact.position;
    final elapsed = (event.timeStamp - contact.timestamp).inMicroseconds / 1000;
    contact.position = event.localPosition;
    contact.timestamp = event.timeStamp;
    if ((contact.position - contact.start).distance > _slop) _moved = true;

    if (_maxContacts == 1) {
      _uncommitted += delta;
      if (!_moved && !_dragging) return;
      _holdTimer?.cancel();
      _commitTap();
      final v = delta.distance / elapsed.clamp(1.0, 50.0);
      _velocity = _velocity * .65 + v.clamp(0.0, 3.0) * .35;
      _move += _uncommitted * widget.speed * (1 + .35 * _velocity);
      _uncommitted = Offset.zero;
      _schedule();
    } else if (_maxContacts == 2 && _contacts.length == 2) {
      // Each contact contributes half of the centroid movement. The sign
      // follows the fingers, matching macOS natural scrolling.
      _uncommitted += delta / 2;
      if (!_moved) return;
      _scroll += _uncommitted;
      _uncommitted = Offset.zero;
      _schedule();
    }
  }

  void _up(PointerUpEvent event) {
    if (!_contacts.containsKey(event.pointer)) return;
    _holdTimer?.cancel();
    _contacts.remove(event.pointer);
    if (_contacts.isNotEmpty) return;
    if (_dragging) {
      _releasePending = true;
      _schedule();
    } else if (!_moved &&
        !_cancelled &&
        event.timeStamp - _started < const Duration(milliseconds: 350)) {
      if (_maxContacts == 2) {
        _commitTap();
        widget.send(const RemoteInput.click(RemoteButton.right));
        HapticFeedback.selectionClick();
      } else if (_maxContacts == 1) {
        HapticFeedback.selectionClick();
        if (_tapTimer != null && (_start - _lastTap!).distance < 24) {
          _tapTimer!.cancel();
          _tapTimer = null;
          widget.send(const RemoteInput.click(RemoteButton.left, count: 2));
        } else {
          _commitTap();
          _lastTap = _start;
          _tapTimer = Timer(_doubleTapWindow, _commitTap);
        }
      }
    }
  }

  void _commitTap() {
    if (_tapTimer == null) return;
    _tapTimer!.cancel();
    _tapTimer = null;
    if (widget.enabled) widget.send(const RemoteInput.click(RemoteButton.left));
  }

  void _schedule() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    _frame = null;
    if (!mounted || !widget.enabled) return;
    if (_lastFrame != null &&
        timestamp - _lastFrame! < const Duration(microseconds: 8333)) {
      _schedule();
      return;
    }
    _lastFrame = timestamp;
    if (_move != Offset.zero) {
      widget.send(RemoteInput.move(_move.dx, _move.dy));
      _move = Offset.zero;
    }
    if (_scroll != Offset.zero) {
      // A short low-pass tail removes raw-event jitter without losing distance.
      final step = _scroll.distance < .2 ? _scroll : _scroll * .65;
      widget.send(RemoteInput.scroll(step.dx, step.dy));
      _scroll -= step;
    }
    if (_releasePending) _finishDrag();
    if (_scroll != Offset.zero) _schedule();
  }

  void _finishDrag() {
    if (!_dragging) return;
    if (_move != Offset.zero && widget.enabled) {
      widget.send(RemoteInput.move(_move.dx, _move.dy));
      _move = Offset.zero;
    }
    // Release even during disposal or loss of trust; the engine safely gates it.
    widget.send(const RemoteInput.drag(down: false));
    _dragging = false;
    _releasePending = false;
  }

  void _reset() {
    _holdTimer?.cancel();
    _tapTimer?.cancel();
    _tapTimer = null;
    if (_frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
    }
    _frame = null;
    _move = Offset.zero;
    _scroll = Offset.zero;
    _contacts.clear();
    _finishDrag();
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Trackpad. Tik om te klikken. Veeg met twee vingers om te scrollen.',
    onTap: widget.enabled
        ? () {
            widget.send(const RemoteInput.click(RemoteButton.left));
            HapticFeedback.selectionClick();
          }
        : null,
    child: Listener(
      key: const ValueKey('trackpad-surface'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _motion,
      onPointerUp: _up,
      onPointerCancel: (_) => _reset(),
      child: GestureDetector(
        // Claim the surface so the surrounding short-screen scroll view cannot
        // scroll the UI while the user is moving the Mac pointer.
        onScaleStart: widget.enabled ? (_) {} : null,
        onScaleUpdate: widget.enabled ? (_) {} : null,
        child: Container(
          decoration: BoxDecoration(
            color: DotColors.muted(context),
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _touched ? 0 : 1,
              duration: widget.reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 32,
                    color: DotColors.secondary(context),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Beweeg met één vinger',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tik om te klikken\nTwee vingers om te scrollen\nHoud vast om te slepen',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
