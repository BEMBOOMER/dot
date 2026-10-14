import 'package:dot/core/remote_input.dart';
import 'package:dot/core/typing_diff.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> wires(List<RemoteInput> inputs) =>
    inputs.map((i) => i.toWire()).toList();

void main() {
  group('TypingDiff', () {
    test('typing appends text', () {
      final diff = TypingDiff.between('Hal', 'Hallo');
      expect(diff.backspaces, 0);
      expect(diff.inserted, 'lo');
    });

    test('deleting sends backspaces', () {
      final diff = TypingDiff.between('Hallo', 'Hal');
      expect(diff.backspaces, 2);
      expect(diff.inserted, '');
    });

    test('autocorrect replaces the changed tail only', () {
      final diff = TypingDiff.between('ik ben moe ', 'ik ben moeë ');
      expect(diff.backspaces, 1);
      expect(diff.inserted, 'ë ');
      final swap = TypingDiff.between('teh', 'the ');
      expect(swap.backspaces, 2);
      expect(swap.inserted, 'he ');
    });

    test('emoji count as one character', () {
      final diff = TypingDiff.between('hoi 👨‍👩‍👧', 'hoi ');
      expect(diff.backspaces, 1);
      expect(TypingDiff.between('a', 'a👍🏽').inserted, '👍🏽');
    });

    test('no change is empty', () {
      expect(TypingDiff.between('abc', 'abc').isEmpty, isTrue);
    });

    test('newlines and tabs become keys, long text is split', () {
      expect(wires(TypingDiff.between('', 'a\nb\tc').toInputs()), [
        const RemoteInput.text('a').toWire(),
        const RemoteInput.edit(EditKey.enter).toWire(),
        const RemoteInput.text('b').toWire(),
        const RemoteInput.edit(EditKey.tab).toWire(),
        const RemoteInput.text('c').toWire(),
      ]);
      final long = TypingDiff.textToInputs('x' * 150);
      expect(long.length, 3);
      for (final input in long) {
        expect(RemoteInput.fromWire(input.toWire()), isNotNull);
      }
      expect(long.map((i) => (i as TypedText).text).join(), 'x' * 150);
    });

    test('splitting never breaks a surrogate pair', () {
      final text = '${'x' * 63}😀😀';
      final chunks = RemoteInput.chunkText(text);
      expect(chunks.join(), text);
      for (final chunk in chunks) {
        expect(RemoteInput.validText(chunk), isTrue);
      }
    });
  });

  group('text wire format', () {
    test('round-trips text and edit keys', () {
      for (final input in [
        const RemoteInput.text('Ça va? 👋'),
        for (final key in EditKey.values) RemoteInput.edit(key),
      ]) {
        expect(RemoteInput.fromWire(input.toWire())?.toWire(), input.toWire());
      }
    });

    test('rejects control characters, oversize and broken text', () {
      for (final text in ['', 'a\nb', 'a\u0007', 'x' * 65, '\uD83D', 'a\uDE00']) {
        expect(
          RemoteInput.fromWire({'t': 'input', 'k': 'text', 's': text}),
          isNull,
          reason: text,
        );
      }
      expect(
        RemoteInput.fromWire({'t': 'input', 'k': 'text', 's': 'a', 'x': 1}),
        isNull,
      );
      expect(
        RemoteInput.fromWire({'t': 'input', 'k': 'edit', 'key': 'f1'}),
        isNull,
      );
    });

    test('text focus validates its fields', () {
      const focus = TextFocus(active: true, field: 4);
      expect(TextFocus.fromWire(focus.toWire()), focus);
      expect(
        TextFocus.fromWire({'t': 'text_focus', 'active': 'yes', 'field': 1}),
        isNull,
      );
      expect(TextFocus.fromWire({'t': 'text_focus', 'active': true}), isNull);
    });
  });
}
