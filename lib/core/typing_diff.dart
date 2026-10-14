import 'package:flutter/widgets.dart' show StringCharacters;

import 'remote_input.dart';

/// Turns edits in the phone's text field into keystrokes for the Mac.
///
/// The phone field keeps its cursor at the end, so every edit (typing,
/// autocorrect, a swipe word, deleting) is a shared prefix, some characters
/// removed from the end and some text added. Removed characters become
/// backspaces; added text becomes text input, with newlines and tabs sent as
/// their own keys.
class TypingDiff {
  final int backspaces;
  final String inserted;
  const TypingDiff(this.backspaces, this.inserted);

  static TypingDiff between(String before, String after) {
    final a = before.characters.toList();
    final b = after.characters.toList();
    var prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }
    return TypingDiff(a.length - prefix, b.skip(prefix).join());
  }

  bool get isEmpty => backspaces == 0 && inserted.isEmpty;

  /// Inputs in send order.
  List<RemoteInput> toInputs() => [
    for (var i = 0; i < backspaces; i++)
      const RemoteInput.edit(EditKey.backspace),
    ...textToInputs(inserted),
  ];

  static List<RemoteInput> textToInputs(String text) {
    final inputs = <RemoteInput>[];
    final run = StringBuffer();
    void flush() {
      for (final chunk in RemoteInput.chunkText(run.toString())) {
        inputs.add(RemoteInput.text(chunk));
      }
      run.clear();
    }

    for (final char in text.replaceAll('\r\n', '\n').characters) {
      if (char == '\n' || char == '\r') {
        flush();
        inputs.add(const RemoteInput.edit(EditKey.enter));
      } else if (char == '\t') {
        flush();
        inputs.add(const RemoteInput.edit(EditKey.tab));
      } else {
        run.write(char);
      }
    }
    flush();
    return inputs;
  }
}
