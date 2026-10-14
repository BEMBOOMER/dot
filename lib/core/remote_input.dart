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

/// Editing keys for typing on the Mac from the phone keyboard.
enum EditKey { backspace, enter, tab, left, right, up, down }

/// Ephemeral input, never stored in the repository or retried after reconnect.
@immutable
sealed class RemoteInput {
  static const double maxDelta = 2000;

  /// Longest text payload in UTF-16 code units. Longer input is split.
  static const int maxText = 64;

  const RemoteInput();
  const factory RemoteInput.move(double dx, double dy) = PointerMove;
  const factory RemoteInput.click(RemoteButton button, {int count}) =
      PointerClick;
  const factory RemoteInput.drag({required bool down}) = PointerDrag;
  const factory RemoteInput.scroll(double dx, double dy) = PointerScroll;
  const factory RemoteInput.key(RemoteKey key) = PresentationKey;
  const factory RemoteInput.media(RemoteMedia media) = MediaKey;
  const factory RemoteInput.text(String text) = TypedText;
  const factory RemoteInput.edit(EditKey key) = EditKeyPress;

  /// Printable text only: no control characters (use [EditKey] for those)
  /// and no lone surrogates.
  static bool validText(String text) {
    if (text.isEmpty || text.length > maxText) return false;
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c < 0x20 || (c >= 0x7f && c < 0xa0)) return false;
      if (c >= 0xd800 && c <= 0xdbff) {
        if (i + 1 >= units.length) return false;
        final next = units[i + 1];
        if (next < 0xdc00 || next > 0xdfff) return false;
        i++;
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  /// Splits [text] into valid payloads without breaking surrogate pairs.
  /// Control characters are dropped, except newlines and tabs which the
  /// caller should send as [EditKey]s; those are dropped here too.
  static List<String> chunkText(String text) {
    final clean = StringBuffer();
    for (final rune in text.runes) {
      if (rune < 0x20 || (rune >= 0x7f && rune < 0xa0)) continue;
      clean.writeCharCode(rune);
    }
    final chunks = <String>[];
    var current = StringBuffer();
    for (final rune in clean.toString().runes) {
      final char = String.fromCharCode(rune);
      if (current.length + char.length > maxText) {
        chunks.add(current.toString());
        current = StringBuffer();
      }
      current.write(char);
    }
    if (current.isNotEmpty) chunks.add(current.toString());
    return chunks;
  }

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
      case 'text':
        if (!fields({'t', 'k', 's'})) return null;
        final text = value['s'];
        if (text is! String || !validText(text)) return null;
        return TypedText(text);
      case 'edit':
        if (!fields({'t', 'k', 'key'})) return null;
        for (final key in EditKey.values) {
          if (value['key'] == key.name) return EditKeyPress(key);
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

final class TypedText extends RemoteInput {
  final String text;
  const TypedText(this.text);
  @override
  Map<String, Object?> toWire() => {'t': 'input', 'k': 'text', 's': text};
}

final class EditKeyPress extends RemoteInput {
  final EditKey key;
  const EditKeyPress(this.key);
  @override
  Map<String, Object?> toWire() => {'t': 'input', 'k': 'edit', 'key': key.name};
}

/// Host to client: whether a text field on the Mac has keyboard focus.
/// [field] changes whenever focus moves to a different text field, so the
/// phone can offer its keyboard again after the user dismissed it.
@immutable
class TextFocus {
  final bool active;
  final int field;
  const TextFocus({this.active = false, this.field = 0});

  Map<String, Object?> toWire() => {
    't': 'text_focus',
    'active': active,
    'field': field,
  };

  static TextFocus? fromWire(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        value['t'] != 'text_focus' ||
        value['active'] is! bool ||
        value['field'] is! int) {
      return null;
    }
    return TextFocus(
      active: value['active'] as bool,
      field: value['field'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextFocus && active == other.active && field == other.field;
  @override
  int get hashCode => Object.hash(active, field);
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
