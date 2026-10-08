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

/// A half-open character range `[start, end)` within a string.
class WordRange {
  const WordRange(this.start, this.end);

  final int start;
  final int end;

  bool get isEmpty => start == end;

  @override
  bool operator ==(Object other) =>
      other is WordRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'WordRange($start, $end)';
}

/// Word semantics shared by cursor movement, selection, and deletion.
///
/// A word is a run of letters, digits, or underscores; everything else —
/// whitespace, punctuation, symbols — separates words.
class WordNavigation {
  const WordNavigation(this.jumpStyle);

  final WordJumpStyle jumpStyle;

  static final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);
  static final _whitespace = RegExp(r'\s');

  static bool isWordCharacter(String char) => _wordCharacter.hasMatch(char);

  /// The run under [offset], selected as a unit: a word, a stretch of
  /// whitespace, or a stretch of punctuation and symbols.
  ///
  /// [offset] is clamped onto the text, so an offset at the very end selects
  /// the last run. Empty text yields an empty range at 0.
  static WordRange rangeAt(String text, int offset) {
    if (text.isEmpty) return const WordRange(0, 0);
    final anchor = offset.clamp(0, text.length - 1);
    final category = _categoryOf(text[anchor]);

    var start = anchor;
    while (start > 0 && _categoryOf(text[start - 1]) == category) {
      start--;
    }
    var end = anchor + 1;
    while (end < text.length && _categoryOf(text[end]) == category) {
      end++;
    }
    return WordRange(start, end);
  }

  static _CharacterCategory _categoryOf(String char) {
    if (_wordCharacter.hasMatch(char)) return _CharacterCategory.word;
    if (_whitespace.hasMatch(char)) return _CharacterCategory.whitespace;
    return _CharacterCategory.other;
  }

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

enum _CharacterCategory { word, whitespace, other }
