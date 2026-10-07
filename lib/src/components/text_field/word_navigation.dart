import 'dart:io';

/// Where a forward word jump stops.
enum WordJumpStyle {
  /// The end of the current word, as readline and macOS/Linux shells do.
  endOfWord,

  /// The start of the next word, as Windows and PSReadLine do.
  startOfNextWord;

  /// The convention of the shell the host platform ships with.
  static WordJumpStyle get host =>
      Platform.isWindows ? startOfNextWord : endOfWord;
}

/// Word semantics shared by cursor movement, selection, and deletion.
///
/// A word is a run of letters, digits, or underscores; everything else —
/// whitespace, punctuation, symbols — separates words.
class WordNavigation {
  const WordNavigation(this.jumpStyle);

  final WordJumpStyle jumpStyle;

  static final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  static bool isWordCharacter(String char) => _wordCharacter.hasMatch(char);

  /// Where a jump from [offset] in [direction] (-1 or 1) lands.
  int jump(String text, int offset, int direction) =>
      direction < 0 ? previousStart(text, offset) : nextStop(text, offset);

  /// Start of the word at or before [offset].
  int previousStart(String text, int offset) {
    final wordEnd = _skipBackward(text, offset, isWord: false);
    return _skipBackward(text, wordEnd, isWord: true);
  }

  /// Where a forward jump from [offset] lands, per [jumpStyle].
  int nextStop(String text, int offset) {
    switch (jumpStyle) {
      case WordJumpStyle.endOfWord:
        final wordStart = _skipForward(text, offset, isWord: false);
        return _skipForward(text, wordStart, isWord: true);
      case WordJumpStyle.startOfNextWord:
        final wordEnd = _skipForward(text, offset, isWord: true);
        return _skipForward(text, wordEnd, isWord: false);
    }
  }

  /// Start of the run of word characters ending at or spanning [offset].
  int wordStart(String text, int offset) =>
      _skipBackward(text, offset, isWord: true);

  /// End of the run of word characters starting at or spanning [offset].
  int wordEnd(String text, int offset) =>
      _skipForward(text, offset, isWord: true);

  static int _skipBackward(String text, int offset, {required bool isWord}) {
    var i = offset.clamp(0, text.length);
    while (i > 0 && isWordCharacter(text[i - 1]) == isWord) {
      i--;
    }
    return i;
  }

  static int _skipForward(String text, int offset, {required bool isWord}) {
    var i = offset.clamp(0, text.length);
    while (i < text.length && isWordCharacter(text[i]) == isWord) {
      i++;
    }
    return i;
  }
}
