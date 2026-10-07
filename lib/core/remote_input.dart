import 'package:flutter/foundation.dart';

enum RemoteButton { left, right }

enum RemoteKey {
  next,
  prev,
  start,
  startKeynote,
  end,
  blackout,
  escape,
  space;

  String get wireName => this == startKeynote ? 'start_keynote' : name;
}

enum RemoteMedia { playpause, next, prev, volup, voldown, mute }

/// Ephemeral input, never stored in the repository or retried after reconnect.
@immutable
sealed class RemoteInput {
  static const double maxDelta = 2000;

  const RemoteInput();
  const factory RemoteInput.move(double dx, double dy) = PointerMove;
  const factory RemoteInput.click(RemoteButton button, {int count}) =
      PointerClick;
  const factory RemoteInput.drag({required bool down}) = PointerDrag;
  const factory RemoteInput.scroll(double dx, double dy) = PointerScroll;
  const factory RemoteInput.key(RemoteKey key) = PresentationKey;
  const factory RemoteInput.media(RemoteMedia media) = MediaKey;

  Map<String, Object?> toWire();

  /// Reject malformed, oversized, non-finite and unknown incoming input.
  /// Outbound deltas are clamped by [toWire]; inbound deltas must be in range.
  static RemoteInput? fromWire(Object? value) {
    if (value is! Map || value['t'] != 'input') return null;
    bool fields(Set<String> keys) =>
        value.length == keys.length && value.keys.every(keys.contains);
    double? delta(String key) {
      final v = value[key];
      if (v is! num || !v.isFinite || v.abs() > maxDelta) return null;
      return v.toDouble();
    }

    switch (value['k']) {
      case 'move':
      case 'scroll':
        if (!fields({'t', 'k', 'dx', 'dy'})) return null;
        final dx = delta('dx');
        final dy = delta('dy');
        if (dx == null || dy == null) return null;
        return value['k'] == 'move'
            ? PointerMove(dx, dy)
            : PointerScroll(dx, dy);
      case 'click':
        if (!fields({'t', 'k', 'b', 'n'})) return null;
        final button = switch (value['b']) {
          'left' => RemoteButton.left,
          'right' => RemoteButton.right,
          _ => null,
        };
        final count = value['n'];
        if (button == null || count is! int || (count != 1 && count != 2)) {
          return null;
        }
        return PointerClick(button, count: count);
      case 'drag':
        if (!fields({'t', 'k', 's'})) return null;
        return switch (value['s']) {
          'down' => const PointerDrag(down: true),
          'up' => const PointerDrag(down: false),
          _ => null,
        };
      case 'key':
        if (!fields({'t', 'k', 'key'})) return null;
        for (final key in RemoteKey.values) {
          if (value['key'] == key.wireName) return PresentationKey(key);
        }
        return null;
      case 'media':
        if (!fields({'t', 'k', 'm'})) return null;
        for (final media in RemoteMedia.values) {
          if (value['m'] == media.name) return MediaKey(media);
        }
        return null;
      default:
        return null;
    }
  }

  static double _clamp(double value) =>
      value.isFinite ? value.clamp(-maxDelta, maxDelta).toDouble() : value;
}

final class PointerMove extends RemoteInput {
  final double dx;
  final double dy;
  const PointerMove(this.dx, this.dy);
  @override
  Map<String, Object?> toWire() => {
    't': 'input',
    'k': 'move',
    'dx': RemoteInput._clamp(dx),
    'dy': RemoteInput._clamp(dy),
  };
}

final class PointerClick extends RemoteInput {
  final RemoteButton button;
  final int count;
  const PointerClick(this.button, {this.count = 1});
  @override
  Map<String, Object?> toWire() => {
    't': 'input',
    'k': 'click',
    'b': button.name,
    'n': count,
  };
}

final class PointerDrag extends RemoteInput {
  final bool down;
  const PointerDrag({required this.down});
  @override
  Map<String, Object?> toWire() => {
    't': 'input',
    'k': 'drag',
    's': down ? 'down' : 'up',
  };
}

final class PointerScroll extends RemoteInput {
  final double dx;
  final double dy;
  const PointerScroll(this.dx, this.dy);
  @override
  Map<String, Object?> toWire() => {
    't': 'input',
    'k': 'scroll',
    'dx': RemoteInput._clamp(dx),
    'dy': RemoteInput._clamp(dy),
  };
}

final class PresentationKey extends RemoteInput {
  final RemoteKey key;
  const PresentationKey(this.key);
  @override
  Map<String, Object?> toWire() => {
    't': 'input',
    'k': 'key',
    'key': key.wireName,
  };
}

final class MediaKey extends RemoteInput {
  final RemoteMedia media;
  const MediaKey(this.media);
  @override
  Map<String, Object?> toWire() => {
    't': 'input',
    'k': 'media',
    'm': media.name,
  };
}

@immutable
class RemoteInputStatus {
  final bool enabled;
  final bool trusted;

  /// Host: an input sink exists. Client: a connected host supports input.
  final bool available;
  const RemoteInputStatus({
    this.enabled = false,
    this.trusted = false,
    this.available = false,
  });

  Map<String, Object?> toWire() => {
    't': 'input_status',
    'enabled': enabled,
    'trusted': trusted,
  };

  static RemoteInputStatus? fromWire(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        value['t'] != 'input_status' ||
        value['enabled'] is! bool ||
        value['trusted'] is! bool) {
      return null;
    }
    return RemoteInputStatus(
      enabled: value['enabled'] as bool,
      trusted: value['trusted'] as bool,
      available: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteInputStatus &&
      enabled == other.enabled &&
      trusted == other.trusted &&
      available == other.available;
  @override
  int get hashCode => Object.hash(enabled, trusted, available);
}
